//
//  SMCKeys.swift
//  BreezyMac — Shared
//
//  SMC key vocabulary (fan + temperature) and a high-level read facade used by
//  the app for live telemetry. Key set and sensor fallback lists follow the
//  Fanny reference, which reads correctly on modern Apple Silicon.
//

import Foundation

enum SMCKey {
    // Fan telemetry / control keys, parameterized by fan index.
    static func fanCount() -> String { "FNum" }
    static func fanActualRPM(_ i: Int) -> String { "F\(i)Ac" }
    static func fanMinRPM(_ i: Int) -> String { "F\(i)Mn" }
    static func fanMaxRPM(_ i: Int) -> String { "F\(i)Mx" }
    static func fanTargetRPM(_ i: Int) -> String { "F\(i)Tg" }
    static func fanID(_ i: Int) -> String { "F\(i)ID" }

    // Mode key case differs across Apple Silicon revisions ("F0Md" vs "F0md").
    static func fanModeUpper(_ i: Int) -> String { "F\(i)Md" }
    static func fanModeLower(_ i: Int) -> String { "F\(i)md" }

    // Apple-Silicon manual-control unlock gate.
    static let appleSiliconTestMode = "Ftst"
    // Intel forced-fan selector bitmask.
    static let intelForceBits = "FS! "

    // Temperature sensor fallback lists — first plausible reading wins.
    static let cpuTemp = ["TC0P", "TC0D", "TC0F", "TC1C", "TCAD", "TCBD",
                          "Tp09", "Tp0T", "Tp01", "Tp05", "Tp0D", "Tp0C", "Tp0g", "Tp0h", "Te0S"]
    static let gpuTemp = ["TG0D", "TG0H", "TG0P", "Tg05", "Tg0j", "Tg0g", "Tg01", "Tg0c"]
    static let batteryTemp = ["TB0T", "TB1T", "TB2T", "Tw0P", "Ts0P", "Th0H"]
}

/// Snapshot of a single fan's live telemetry.
struct FanReading: Codable, Equatable, Identifiable {
    var id: Int { index }
    var index: Int
    var name: String
    var actualRPM: Int
    var minRPM: Int
    var maxRPM: Int
    var targetRPM: Int
}

/// A full telemetry snapshot the app polls and renders.
struct TelemetrySnapshot: Codable, Equatable {
    var fans: [FanReading] = []
    var cpuTemp: Double? = nil
    var gpuTemp: Double? = nil
    var batteryTemp: Double? = nil
}

/// High-level SMC reader. Wraps an `SMCConnection` and exposes fan/temperature
/// telemetry. Reads only — safe to use from the unprivileged app.
final class SMCReader {
    private let smc = SMCConnection()

    /// Static per-fan bounds (count, min/max RPM, name). These do not change at
    /// runtime, so we resolve them once and reuse — the per-tick reads then only
    /// touch the live values (actual/target RPM).
    struct FanBounds { let index: Int; let name: String; let minRPM: Int; let maxRPM: Int }
    private var boundsCache: [FanBounds]?

    /// Resolved temperature keys, cached after first discovery so we stop
    /// re-probing the long fallback lists every tick. `.none` = not yet probed;
    /// a stored value of `""` records "probed, none present on this hardware".
    private var cpuKeyCache: String?
    private var gpuKeyCache: String?
    private var batteryKeyCache: String?

    func start() {
        try? smc.open()
    }

    func stop() {
        smc.close()
        boundsCache = nil
        cpuKeyCache = nil; gpuKeyCache = nil; batteryKeyCache = nil
    }

    var isReady: Bool { smc.isOpen }

    func fanCount() -> Int {
        guard let v = smc.readDouble(SMCKey.fanCount()) else { return 0 }
        return Int(v)
    }

    /// Cached static bounds for every fan (safe to call every tick).
    func fanBounds() -> [FanBounds] {
        if let cached = boundsCache { return cached }
        let count = fanCount()
        let bounds = (0..<count).map { i in
            FanBounds(index: i,
                      name: readFanName(i) ?? "Fan \(i + 1)",
                      minRPM: intOr0(SMCKey.fanMinRPM(i)),
                      maxRPM: intOr0(SMCKey.fanMaxRPM(i)))
        }
        boundsCache = bounds
        return bounds
    }

    /// Temperatures only — the minimal read Adaptive mode needs while no UI is
    /// visible. Uses cached sensor keys.
    func temperatures() -> (cpu: Double?, gpu: Double?, battery: Double?) {
        (cachedTemp(&cpuKeyCache, SMCKey.cpuTemp),
         cachedTemp(&gpuKeyCache, SMCKey.gpuTemp),
         cachedTemp(&batteryKeyCache, SMCKey.batteryTemp))
    }

    /// Full snapshot for the UI: static bounds (cached) + live actual/target RPM
    /// + temperatures.
    func snapshot() -> TelemetrySnapshot {
        var snap = TelemetrySnapshot()
        snap.fans = fanBounds().map { b in
            FanReading(index: b.index, name: b.name,
                       actualRPM: intOr0(SMCKey.fanActualRPM(b.index)),
                       minRPM: b.minRPM, maxRPM: b.maxRPM,
                       targetRPM: intOr0(SMCKey.fanTargetRPM(b.index)))
        }
        let temps = temperatures()
        snap.cpuTemp = temps.cpu
        snap.gpuTemp = temps.gpu
        snap.batteryTemp = temps.battery
        return snap
    }

    // MARK: - Helpers

    private func intOr0(_ key: String) -> Int {
        guard let v = smc.readDouble(key) else { return 0 }
        return Int(v.rounded())
    }

    /// Read a temperature using a cached key when known; otherwise probe the
    /// fallback list once and remember the result (including "none present").
    private func cachedTemp(_ cache: inout String?, _ keys: [String]) -> Double? {
        if let key = cache {
            if key.isEmpty { return nil }                       // known-absent
            if let v = smc.readDouble(key), v > 0, v < 150 { return v }
            // Cached key stopped reporting — fall through to re-probe.
        }
        for key in keys {
            if let v = smc.readDouble(key), v > 0, v < 150 {
                cache = key
                return v
            }
        }
        cache = ""                                              // probed, none present
        return nil
    }

    private func readFanName(_ i: Int) -> String? {
        guard let value = smc.read(SMCKey.fanID(i)), value.bytes.count > 4 else { return nil }
        // Fan ID payload carries an ASCII label starting at byte 4.
        let nameBytes = value.bytes[4...].prefix { $0 != 0 }
        let name = String(bytes: nameBytes, encoding: .ascii)?.trimmingCharacters(in: .whitespaces)
        return (name?.isEmpty == false) ? name : nil
    }
}
