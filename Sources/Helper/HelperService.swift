//
//  HelperService.swift
//  BreezyMac — Helper (privileged)
//
//  The XPC-exported object plus the single resident fan-control engine that
//  owns the SMC write connection and the safety watchdog.
//
//  Safety invariant: the helper NEVER holds fan control open without a live
//  app heartbeat. If pings stop for longer than kHelperWatchdogTimeout — app
//  quit, crash, sleep, or lid close — the watchdog returns every fan to macOS
//  auto. This is what makes "no influence when the UI is not active" true even
//  when the app dies without a clean handoff.
//

import Foundation

/// Single resident owner of the SMC write path, watchdog, and control state.
final class FanControlEngine {
    static let shared = FanControlEngine()

    private let queue = DispatchQueue(label: "org.WhoCo.BreezyMac.Helper.engine")
    private let fan = FanSMC()
    private var watchdog: DispatchSourceTimer?
    private var engaged = false
    private var lastActivity = Date()

    private init() {
        startWatchdog()
    }

    // MARK: XPC-facing operations (already hopped onto `queue`)

    func heartbeat() {
        queue.async { self.touch() }
    }

    func applyTargets(_ targets: [Int]) -> (Bool, String?) {
        queue.sync {
            touch()
            do {
                try fan.ensureOpen()
                let count = fan.fanCount
                guard count > 0 else { return (false, "No controllable fans reported by SMC") }
                for i in 0..<count {
                    guard i < targets.count else { continue }
                    let t = targets[i]
                    if t == kFanTargetAuto {
                        try fan.setAuto(fanIndex: i)
                    } else {
                        try fan.setManual(fanIndex: i, rpm: Double(t))
                    }
                }
                engaged = targets.contains { $0 != kFanTargetAuto }
                return (true, nil)
            } catch {
                return (false, "\(error)")
            }
        }
    }

    @discardableResult
    func release() -> (Bool, String?) {
        queue.sync {
            fan.releaseAll()
            engaged = false
            lastActivity = Date()
            return (true, nil)
        }
    }

    func dumpKeys() -> String {
        queue.sync { fan.dumpKeys() }
    }

    // MARK: Watchdog

    private func touch() {
        lastActivity = Date()
    }

    private func startWatchdog() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1.0)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            guard self.engaged else { return }
            if Date().timeIntervalSince(self.lastActivity) > kHelperWatchdogTimeout {
                NSLog("BreezyMac helper: watchdog fired — no heartbeat, releasing fan control to macOS")
                self.fan.releaseAll()
                self.engaged = false
            }
        }
        timer.resume()
        watchdog = timer
    }
}

/// Per-connection XPC object. Thin forwarding shim to the shared engine.
final class HelperService: NSObject, HelperProtocol {
    func getVersion(reply: @escaping (String) -> Void) {
        reply(kHelperVersion)
    }

    func heartbeat(reply: @escaping (Bool) -> Void) {
        FanControlEngine.shared.heartbeat()
        reply(true)
    }

    func applyFanTargets(_ targets: [Int], reply: @escaping (Bool, String?) -> Void) {
        let (ok, err) = FanControlEngine.shared.applyTargets(targets)
        reply(ok, err)
    }

    func releaseControl(reply: @escaping (Bool, String?) -> Void) {
        let (ok, err) = FanControlEngine.shared.release()
        reply(ok, err)
    }

    func dumpFanKeys(reply: @escaping (String) -> Void) {
        reply(FanControlEngine.shared.dumpKeys())
    }

    /// Called from signal handlers on daemon teardown — best-effort handoff.
    static func cleanupOnExit() {
        FanControlEngine.shared.release()
    }
}
