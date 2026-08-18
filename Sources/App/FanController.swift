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
//  Polling cadence is demand-driven:
//   • The tick timer runs only when an engaging mode is active OR some UI is
//     visible. In Disabled mode with no window/menu open, the timer is stopped
//     entirely, so the app truly idles at ~0% CPU.
//   • When engaged but no UI is visible, a tick does the minimum: a heartbeat
//     (always) and, for Adaptive only, a temperatures-only read for the curve.
//     A full sensor snapshot is taken only when UI is on screen to display it.
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

    // Visibility of any UI that needs live telemetry.
    private var menuVisible = false
    private var windowVisible = false
    private var uiVisible: Bool { menuVisible || windowVisible }

    private let tickInterval: TimeInterval = kHelperHeartbeatInterval
    /// Adaptive re-apply deadband: ignore sub-threshold target drift so a slowly
    /// varying temperature doesn't cause a continuous stream of SMC writes.
    private let reapplyDeadbandRPM = 50

    /// The timer must run while we're either controlling fans (heartbeat needed)
    /// or showing live data. Otherwise it stops and the app idles.
    private var shouldPoll: Bool { state.mode.engagesHelper || uiVisible }

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
            case .ready:        self.applyCurrentMode()
            case .notInstalled: self.installRequested = false   // allow re-install after uninstall
            default:            break
            }
        }
        helper.onVersion = { [weak self] version in self?.state.helperVersion = version }

        state.onModeChange = { [weak self] _ in self?.applyCurrentMode() }

        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        nc.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)

        // Do NOT auto-install the privileged daemon. In the default Disabled
        // mode the app must have zero system influence. We register lazily the
        // first time an engaging mode actually needs it (or via the UI button).
        helper.refreshStatus()

        // One initial read so the first menu open shows data immediately, then
        // start polling only if the current mode/visibility warrants it.
        state.telemetry = reader.snapshot()
        updatePolling()
    }

    /// Best-effort synchronous-ish release for app termination.
    func shutdown() {
        stopTimer()
        reader.stop()
        helper.releaseControl()
        // Give the XPC message a brief window to flush before we exit.
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
    }

    // MARK: UI visibility (wired from AppDelegate)

    func setMenuVisible(_ visible: Bool) {
        menuVisible = visible
        if visible { state.telemetry = reader.snapshot() }   // fresh data for the readout
        updatePolling()
    }

    func setWindowVisible(_ visible: Bool) {
        windowVisible = visible
        if visible { state.telemetry = reader.snapshot() }
        updatePolling()
    }

    // MARK: Timer

    private func updatePolling() {
        if shouldPoll {
            if timer == nil { startTimer() }
        } else {
            stopTimer()
        }
    }

    private func startTimer() {
        // `.common` modes so it keeps firing while a menu/modal panel is open
        // (see safety invariant #5); `assumeIsolated` avoids an async hop that a
        // nested run loop could defer.
        let t = Timer(timeInterval: tickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: Tick

    private func tick() {
        guard !asleep else { return }
        if uiVisible {
            state.telemetry = reader.snapshot()              // full read for the UI
        } else if state.mode == .adaptive {
            let t = reader.temperatures()                    // curve only needs temps
            state.telemetry.cpuTemp = t.cpu
            state.telemetry.gpuTemp = t.gpu
            state.telemetry.batteryTemp = t.battery
        }
        // Performance/Silent while hidden: no SMC reads — just heartbeat below.
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
            guard !targets.isEmpty else { return }   // fan bounds not resolved yet
            if shouldReapply(targets) {
                helper.applyFanTargets(targets)
                lastAppliedTargets = targets
            }
            helper.heartbeat()   // keep the watchdog satisfied every tick
            engaged = true
        }
    }

    /// (Re)apply the current mode immediately, e.g. on mode change, helper-ready,
    /// or wake. Also reconciles the polling timer with the new mode.
    private func applyCurrentMode() {
        lastAppliedTargets = []      // force the next drive() to re-apply
        updatePolling()
        if !asleep { drive() }
    }

    // MARK: Target computation

    private func targets(for mode: OperatingMode) -> [Int] {
        let bounds = reader.fanBounds()
        guard !bounds.isEmpty else { return [] }
        switch mode {
        case .disabled:
            return bounds.map { _ in kFanTargetAuto }
        case .silent:
            // Attempt lowest possible; the helper clamps to each fan's floor.
            // TODO: confirm whether true 0-RPM is attainable on M-series.
            return bounds.map { _ in 0 }
        case .performance:
            return bounds.map { $0.maxRPM }
        case .adaptive:
            let frac = state.curveConfig.targetFraction(for: state.telemetry)
            return bounds.map { b in
                Int((Double(b.minRPM) + frac * Double(max(0, b.maxRPM - b.minRPM))).rounded())
            }
        }
    }

    /// True if the new targets differ enough from the last applied set to be
    /// worth another SMC write (count change, or any fan beyond the deadband).
    private func shouldReapply(_ new: [Int]) -> Bool {
        guard new.count == lastAppliedTargets.count else { return true }
        for (a, b) in zip(new, lastAppliedTargets) where abs(a - b) > reapplyDeadbandRPM {
            return true
        }
        return false
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
        applyCurrentMode()
    }
}
