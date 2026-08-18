//
//  FanSMC.swift
//  BreezyMac — Helper (privileged)
//
//  The SMC WRITE path. Root-only. Encapsulates the Apple-Silicon manual-control
//  unlock sequence and the "return to macOS auto" path. Deliberately far more
//  conservative than the Fanny reference (which blocks for seconds and hammers
//  the SMC hundreds of times); we prefer bounded, non-blocking retries and we
//  never claim success unless the SMC write itself succeeded.
//

import Foundation

final class FanSMC {
    private let smc = SMCConnection()
    private var modeKeyIsLower: Bool?          // Apple-Silicon "F0md" vs "F0Md" probe cache
    private var testModeEngaged = false

    // Bounded retry knobs (tunable; intentionally small).
    private let modeWriteAttempts = 8
    private let modeWriteDelay: useconds_t = 60_000   // 60 ms

    func ensureOpen() throws {
        try smc.open()
    }

    var fanCount: Int {
        guard let v = smc.readDouble(SMCKey.fanCount()) else { return 0 }
        return Int(v)
    }

    // MARK: - Public control operations

    /// Force one fan to a target RPM (clamped to the fan's [min, max]).
    func setManual(fanIndex i: Int, rpm: Double) throws {
        try ensureOpen()
        let minRPM = smc.readDouble(SMCKey.fanMinRPM(i)) ?? 0
        let maxRPM = smc.readDouble(SMCKey.fanMaxRPM(i)) ?? rpm
        let clamped = max(minRPM, min(maxRPM, rpm))

        try enableManualMode(fanIndex: i)
        try writeTarget(fanIndex: i, rpm: clamped)
    }

    /// Return one fan to macOS auto control.
    func setAuto(fanIndex i: Int) throws {
        try ensureOpen()
        try writeMode(fanIndex: i, manual: false)
    }

    /// Return ALL fans to macOS auto and clear the Apple-Silicon unlock gate.
    func releaseAll() {
        try? ensureOpen()
        let count = fanCount
        for i in 0..<count {
            try? writeMode(fanIndex: i, manual: false)
        }
        clearTestModeIfNeeded(force: true)
    }

    func dumpKeys() -> String {
        try? ensureOpen()
        var lines: [String] = []
        let count = fanCount
        lines.append("FNum = \(count)")
        for i in 0..<count {
            for key in [SMCKey.fanActualRPM(i), SMCKey.fanMinRPM(i), SMCKey.fanMaxRPM(i),
                        SMCKey.fanTargetRPM(i), modeKey(i)] {
                if let v = smc.read(key) {
                    lines.append("\(key): type=\(v.dataType) size=\(v.dataSize) bytes=\(v.bytes.map { String(format: "%02x", $0) }.joined())")
                } else {
                    lines.append("\(key): <absent>")
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Mode / unlock internals

    private func modeKey(_ i: Int) -> String {
        #if arch(arm64)
        if modeKeyIsLower == nil {
            // Probe once: if the lowercase variant exists, use it.
            modeKeyIsLower = smc.read(SMCKey.fanModeLower(i)) != nil
        }
        return (modeKeyIsLower ?? false) ? SMCKey.fanModeLower(i) : SMCKey.fanModeUpper(i)
        #else
        return SMCKey.fanModeUpper(i)
        #endif
    }

    private func enableManualMode(fanIndex i: Int) throws {
        // Fast path: some Macs (M5+, Intel) accept a direct manual-mode write.
        if (try? writeMode(fanIndex: i, manual: true)) != nil, isManual(fanIndex: i) {
            return
        }
        #if arch(arm64)
        // Apple-Silicon gate: raise Ftst, then re-assert manual mode a bounded
        // number of times, letting thermalmonitord yield between attempts.
        try engageTestMode()
        for _ in 0..<modeWriteAttempts {
            try? writeMode(fanIndex: i, manual: true)
            if isManual(fanIndex: i) { return }
            usleep(modeWriteDelay)
        }
        #endif
        // Even if the readback still says auto (a known Apple-Silicon quirk),
        // proceed — the target write below is what actually spins the fan.
    }

    private func isManual(fanIndex i: Int) -> Bool {
        guard let v = smc.read(modeKey(i)), let first = v.bytes.first else { return false }
        return first == 1
    }

    private func writeMode(fanIndex i: Int, manual: Bool) throws {
        try smc.write(modeKey(i), bytes: [manual ? 1 : 0])
    }

    private func writeTarget(fanIndex i: Int, rpm: Double) throws {
        let key = SMCKey.fanTargetRPM(i)
        guard let existing = smc.read(key) else { throw SMCConnection.SMCError.keyNotFound(key) }
        guard let encoded = SMCDecode.encodeFanTarget(rpm, type: existing.dataType) else {
            throw SMCConnection.SMCError.keyNotFound("\(key)/type=\(existing.dataType)")
        }
        try smc.write(key, bytes: encoded)
    }

    #if arch(arm64)
    private func engageTestMode() throws {
        try smc.write(SMCKey.appleSiliconTestMode, bytes: [1])
        testModeEngaged = true
    }
    #endif

    private func clearTestModeIfNeeded(force: Bool) {
        #if arch(arm64)
        if testModeEngaged || force {
            try? smc.write(SMCKey.appleSiliconTestMode, bytes: [0])
            testModeEngaged = false
        }
        #endif
    }
}
