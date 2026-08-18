//
//  FanController.swift
//  BreezyMac — App
//
//  The control brain. Polls sensors (app-side SMC reads), translates the
//  current OperatingMode into per-fan targets, drives the privileged helper,
//  and enforces the lifecycle safety rules: release on Disabled, on sleep/lid
//  close, and on quit; re-assert on wake. A heartbeat keeps the helper's
//  watchdog satisfied only while the app is genuinely alive and in control.
//

import Foundation
import AppKit

@MainActor
final class FanController {
    private let state = AppState.shared
    private let reader = SMCReader()
    let helper = HelperClient()

    private var timer: Timer?
    private var asleep = false
    private var engaged = false
    private var installRequested = false
    private var lastAppliedTargets: [Int] = []

    private let tickInterval: TimeInterval = kHelperHeartbeatInterval

    private var isHelperReady: Bool {
        if case .ready = state.helperStatus { return true }
        return false
    }

    // MARK: Lifecycle

    func start() {
        reader.start()

        helper.onStatusChange = { [weak self] status in
            guard let self else { return }
            self.state.helperStatus = status
            switch status {
            case .ready:        self.applyCurrentMode(force: true)
            case .notInstalled: self.installRequested = false   // allow re-install after uninstall
            default:            break
            }
        }
        helper.onVersion = { [weak self] version in self?.state.helperVersion = version }

        state.onModeChange = { [weak self] _ in self?.applyCurrentMode(force: true) }

        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        nc.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)

        // Do NOT auto-install the privileged daemon. In the default Disabled
        // mode the app must have zero system influence. We register lazily the
        // first time an engaging mode actually needs it (or via the UI button).
        helper.refreshStatus()

        // IMPORTANT: register the tick/heartbeat timer in `.common` run-loop
        // modes. While the status-bar NSMenu (or any menu/modal panel) is open,
        // AppKit runs a nested run loop in event-tracking mode; a timer in only
        // the default mode would stop firing, the heartbeat would lapse, and the
        // helper's watchdog would (correctly, but unexpectedly) revert fans to
        // macOS auto after ~6 s. We also fire synchronously via assumeIsolated
        // rather than hopping through a Task, so nothing is deferred until the
        // nested loop exits.
        let t = Timer(timeInterval: tickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)
        timer = t
        tick()
    }

    /// Best-effort synchronous-ish release for app termination.
    func shutdown() {
        timer?.invalidate()
        timer = nil
        reader.stop()
        helper.releaseControl()
        // Give the XPC message a brief window to flush before we exit.
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
    }

    // MARK: Tick

    private func tick() {
        state.telemetry = reader.snapshot()
        guard !asleep else { return }
        drive()
    }

    private func drive() {
        switch state.mode {
        case .disabled:
            if engaged {
                helper.releaseControl()
                engaged = false
                lastAppliedTargets = []
            }
        case .silent, .performance, .adaptive:
            // Lazily register the privileged helper the first time control is
            // actually needed. install() is a no-op once ready.
            if !isHelperReady, !installRequested {
                installRequested = true
                helper.install()
            }
            guard isHelperReady else { return }   // waiting on install / user approval

            let targets = targets(for: state.mode)
            guard !targets.isEmpty else { return }   // no telemetry yet
            if targets != lastAppliedTargets {
                helper.applyFanTargets(targets)
                lastAppliedTargets = targets
            }
            helper.heartbeat()   // keep the watchdog satisfied every tick
            engaged = true
        }
    }

    /// Force an immediate (re)apply, e.g. on mode change or helper-ready.
    private func applyCurrentMode(force: Bool) {
        if force { lastAppliedTargets = [] }
        drive()
    }

    // MARK: Target computation

    private func targets(for mode: OperatingMode) -> [Int] {
        let fans = state.telemetry.fans
        guard !fans.isEmpty else { return [] }
        switch mode {
        case .disabled:
            return fans.map { _ in kFanTargetAuto }
        case .silent:
            // Attempt lowest possible; the helper clamps to each fan's floor.
            // TODO: confirm whether true 0-RPM is attainable on M-series.
            return fans.map { _ in 0 }
        case .performance:
            return fans.map { $0.maxRPM }
        case .adaptive:
            let frac = state.curveConfig.targetFraction(for: state.telemetry)
            return fans.map { fan in
                let rpm = Double(fan.minRPM) + frac * Double(max(0, fan.maxRPM - fan.minRPM))
                return Int(rpm.rounded())
            }
        }
    }

    // MARK: Sleep / wake

    @objc private func willSleep() {
        asleep = true
        helper.releaseControl()      // proactively hand back before the machine sleeps
        engaged = false
        lastAppliedTargets = []
    }

    @objc private func didWake() {
        asleep = false
        applyCurrentMode(force: true)
    }
}
