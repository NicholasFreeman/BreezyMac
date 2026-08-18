//
//  HelperProtocol.swift
//  BreezyMac — Shared
//
//  The XPC contract between the unprivileged app and the privileged helper
//  daemon. Compiled into BOTH targets. Modeled on the ChillMac reference, with
//  an added heartbeat so the helper can enforce a watchdog: if the app stops
//  pinging (quit, crash, sleep, lid close), the helper returns all fans to
//  macOS auto on its own. This is the core of the "no influence when the UI is
//  not active" safety guarantee.
//

import Foundation

// Identity used for the mach service, launchd Label, and SMAppService plist.
// All three are identical, and equal to the helper's bundle identifier.
let kHelperMachServiceName = "org.WhoCo.BreezyMac.Helper"

// Compiled version constant used for the XPC version handshake (independent of
// any Info.plist version string, which is easy to let drift).
let kHelperVersion = "0.1.0"

// Timing contract shared by both sides.
let kHelperHeartbeatInterval: TimeInterval = 2.0   // app → helper ping cadence
let kHelperWatchdogTimeout: TimeInterval = 6.0     // helper reverts to auto after this silence

// Sentinel target meaning "leave this fan on macOS auto".
let kFanTargetAuto: Int = -1

@objc protocol HelperProtocol {
    /// Returns the helper's compiled version (`kHelperVersion`) for handshake.
    func getVersion(reply: @escaping (String) -> Void)

    /// Keep-alive. Resets the helper's watchdog. The app calls this on
    /// `kHelperHeartbeatInterval` while any control mode is engaged.
    func heartbeat(reply: @escaping (Bool) -> Void)

    /// Force each fan to the given RPM (manual control). A value of
    /// `kFanTargetAuto` leaves that fan on macOS auto. `targets.count` should
    /// match the fan count; extra/missing entries are ignored. Also (re)arms
    /// the watchdog.
    func applyFanTargets(_ targets: [Int], reply: @escaping (Bool, String?) -> Void)

    /// Return every fan to macOS auto control and clear any unlock state. Called
    /// on mode → Disabled, on app quit, on sleep, and by the watchdog.
    func releaseControl(reply: @escaping (Bool, String?) -> Void)

    /// Diagnostic dump of raw fan-related SMC keys.
    func dumpFanKeys(reply: @escaping (String) -> Void)
}
