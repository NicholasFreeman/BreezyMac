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
    private let automatic = AutomaticController()
    private let powerMonitor = PowerSourceMonitor()

    private var timer: Timer?
    private var asleep = false
    private var engaged = false
    private var installRequested = false
    private var lastAppliedTargets: [Int] = []

    // Visibility of any UI that needs live telemetry.
    private var popoverVisible = false
    private var windowVisible = false
    private var uiVisible: Bool { popoverVisible || windowVisible }

    /// When the charts last took a full display refresh. The control tick fires
    /// every `kHelperHeartbeatInterval`; display refreshes are subsampled from it
    /// at the user's chosen `PopoverSettings.refreshInterval` (never faster).
    private var lastDisplayRefresh: Date = .distantPast

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

        // If the XPC connection drops (daemon respawn), force the next tick to
        // re-apply targets to the freshly-started, control-released helper.
        helper.onConnectionLost = { [weak self] in self?.lastAppliedTargets = [] }

        state.onModeChange = { [weak self] mode in
            guard let self else { return }
            if mode == .automatic { self.automatic.reset() }   // fresh smoothing state
            self.applyCurrentMode()
        }

        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        nc.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        // Thermal pressure is our throttle proxy — react immediately, not on the
        // next 2 s tick, when macOS reports it changed.
        NotificationCenter.default.addObserver(self, selector: #selector(thermalChanged),
                                               name: ProcessInfo.thermalStateDidChangeNotification, object: nil)

        // Track power source and re-apply when it changes (setpoints/curves differ).
        state.thermalState = ProcessInfo.processInfo.thermalState
        state.powerSource = powerMonitor.current()
        powerMonitor.onChange = { [weak self] source in
            guard let self else { return }
            self.state.powerSource = source
            self.applyCurrentMode()
        }
        powerMonitor.start()

        // Do NOT auto-install the privileged daemon. In the default Disabled
        // mode the app must have zero system influence. We register lazily the
        // first time an engaging mode actually needs it (or via the UI button).
        helper.refreshStatus()

        // One initial read so the first menu open shows data immediately, then
        // start polling only if the current mode/visibility warrants it.
        state.telemetry = reader.snapshot()
        updatePolling()
    }

    /// Uninstall the helper safely: switch to Disabled first so control is
    /// released and the lazy re-install loop can't immediately re-register the
    /// daemon, then unregister.
    func requestUninstall() {
        state.mode = .disabled       // releases control + prevents auto re-install
        helper.uninstall()
    }

    /// Best-effort synchronous-ish release for app termination.
    func shutdown() {
        stopTimer()
        powerMonitor.stop()
        reader.stop()
        helper.releaseControl()
        // Give the XPC message a brief window to flush before we exit.
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
    }

    // MARK: UI visibility (wired from AppDelegate)

    func setPopoverVisible(_ visible: Bool) {
        popoverVisible = visible
        if visible { refreshDisplay() }   // fresh charts the instant the popover opens
        updatePolling()
    }

    func setWindowVisible(_ visible: Bool) {
        windowVisible = visible
        if visible { refreshDisplay() }
        updatePolling()
    }

    /// Take a full snapshot for the UI and record it in history, stamping the
    /// display-refresh clock so the throttled tick doesn't immediately repeat it.
    private func refreshDisplay() {
        state.telemetry = reader.snapshot()
        state.appendHistory(from: state.telemetry)
        lastDisplayRefresh = Date()
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
        state.thermalState = ProcessInfo.processInfo.thermalState

        if uiVisible {
            // Refresh the charts at the user's chosen cadence, subsampling this
            // fixed 2 s tick. Between display frames we still keep control temps
            // fresh so Automatic/Adaptive never act on stale readings.
            let now = Date()
            let due = now.timeIntervalSince(lastDisplayRefresh) >= state.popoverSettings.refreshInterval - 0.25
            if due {
                state.telemetry = reader.snapshot()          // full read for the UI
                state.appendHistory(from: state.telemetry)
                lastDisplayRefresh = now
            } else if state.mode.needsTemperature {
                refreshControlTemps()
            }
        } else if state.mode.needsTemperature {
            refreshControlTemps()                            // Automatic/Adaptive need temps while hidden
        }
        // Performance while hidden: no SMC reads — just the heartbeat in drive().
        drive()
    }

    /// Minimal temps-only read to feed the control loop between display frames.
    private func refreshControlTemps() {
        let t = reader.temperatures()
        state.telemetry.cpuTemp = t.cpu
        state.telemetry.gpuTemp = t.gpu
        state.telemetry.batteryTemp = t.battery
    }

    private func drive() {
        switch state.mode {
        case .disabled:
            if engaged {
                helper.releaseControl()
                engaged = false
                lastAppliedTargets = []
            }
        case .automatic, .adaptive, .performance:
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
        case .performance:
            return bounds.map { $0.maxRPM }
        case .automatic:
            let frac = automatic.fraction(cpu: state.telemetry.cpuTemp,
                                          gpu: state.telemetry.gpuTemp,
                                          thermalState: state.thermalState,
                                          source: state.powerSource,
                                          config: state.automaticConfig,
                                          now: Date())
            return bounds.map { fraction(frac, of: $0) }
        case .adaptive:
            let frac = state.curveConfig.targetFraction(for: state.telemetry, source: state.powerSource)
            return bounds.map { fraction(frac, of: $0) }
        }
    }

    /// Map a 0...1 fan fraction to an RPM within a fan's [min, max].
    private func fraction(_ frac: Double, of bounds: SMCReader.FanBounds) -> Int {
        Int((Double(bounds.minRPM) + frac * Double(max(0, bounds.maxRPM - bounds.minRPM))).rounded())
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

    @objc private func thermalChanged() {
        state.thermalState = ProcessInfo.processInfo.thermalState
        // In Automatic, thermal pressure jumps the fans to max — apply now
        // rather than waiting for the next tick.
        if state.mode == .automatic { applyCurrentMode() }
    }
}
