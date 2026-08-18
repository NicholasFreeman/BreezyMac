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

    func start() {
        try? smc.open()
    }

    func stop() {
        smc.close()
    }

    var isReady: Bool { smc.isOpen }

    func fanCount() -> Int {
        guard let v = smc.readDouble(SMCKey.fanCount()) else { return 0 }
        return Int(v)
    }

    func readFan(_ i: Int) -> FanReading {
        let name = readFanName(i) ?? "Fan \(i + 1)"
        return FanReading(
            index: i,
            name: name,
            actualRPM: intOr0(SMCKey.fanActualRPM(i)),
            minRPM: intOr0(SMCKey.fanMinRPM(i)),
            maxRPM: intOr0(SMCKey.fanMaxRPM(i)),
            targetRPM: intOr0(SMCKey.fanTargetRPM(i))
        )
    }

    func snapshot() -> TelemetrySnapshot {
        var snap = TelemetrySnapshot()
        let count = fanCount()
        snap.fans = (0..<count).map(readFan)
        snap.cpuTemp = firstValidTemp(SMCKey.cpuTemp)
        snap.gpuTemp = firstValidTemp(SMCKey.gpuTemp)
        snap.batteryTemp = firstValidTemp(SMCKey.batteryTemp)
        return snap
    }

    // MARK: - Helpers

    private func intOr0(_ key: String) -> Int {
        guard let v = smc.readDouble(key) else { return 0 }
        return Int(v.rounded())
    }

    private func firstValidTemp(_ keys: [String]) -> Double? {
        for key in keys {
            if let v = smc.readDouble(key), v > 0, v < 150 {
                return v
            }
        }
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
