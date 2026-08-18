//
//  SMCTypes.swift
//  BreezyMac — Shared
//
//  Low-level mirrors of the AppleSMC kernel wire structs, plus FourCharCode
//  packing and the fixed-point decoders/encoders the SMC uses for sensor and
//  fan values. This file is intentionally free of IOKit connection logic — see
//  SMCConnection.swift.
//
//  Layout and semantics are derived from the (correct) Apple-Silicon-aware
//  approach in the Fanny reference; the struct field order MUST match what the
//  AppleSMC user client expects.
//

import Foundation

// A raw 32-byte SMC payload. Represented as a homogeneous tuple to match the
// C struct's `UInt8 bytes[32]` exactly.
typealias SMCBytes = (
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
)

let smcBytesZero: SMCBytes = (
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
)

// KERNEL_INDEX_SMC — the single IOConnectCallStructMethod selector used for all
// SMC traffic. The concrete operation is chosen by the `data8` sub-command.
let kSMCKernelIndex: UInt32 = 2

// `data8` sub-commands.
enum SMCSelector: UInt8 {
    case readBytes    = 5
    case writeBytes   = 6
    case readIndex    = 8
    case readKeyInfo  = 9
    case readPLimit   = 11
    case readVers     = 12
}

struct SMCVersion {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

struct SMCPLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

struct SMCKeyInfoData {
    var dataSize: UInt32 = 0       // IOByteCount32
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
}

// The full wire struct passed both directions through IOConnectCallStructMethod.
struct SMCKeyData {
    var key: UInt32 = 0
    var vers = SMCVersion()
    var pLimitData = SMCPLimitData()
    var keyInfo = SMCKeyInfoData()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0           // sub-command (SMCSelector)
    var data32: UInt32 = 0
    var bytes: SMCBytes = smcBytesZero
}

// A decoded/typed SMC value.
struct SMCValue {
    var key: String
    var dataSize: UInt32
    var dataType: String      // 4-char type, e.g. "flt ", "fpe2", "ui16"
    var bytes: [UInt8]        // dataSize meaningful bytes

    init(key: String, dataSize: UInt32 = 0, dataType: String = "", bytes: [UInt8] = []) {
        self.key = key
        self.dataSize = dataSize
        self.dataType = dataType
        self.bytes = bytes
    }
}

// Named FourCC to avoid colliding with the SDK's global `FourCharCode` typealias.
enum FourCC {
    /// Pack a 4-character key (e.g. "F0Tg") big-endian into a UInt32.
    static func from(_ string: String) -> UInt32 {
        precondition(string.count == 4, "SMC keys are exactly 4 characters: \(string)")
        var result: UInt32 = 0
        for byte in string.utf8 {
            result = (result << 8) | UInt32(byte)
        }
        return result
    }

    /// Unpack a UInt32 (e.g. a dataType) into its 4-character string.
    static func toString(_ value: UInt32) -> String {
        let chars = [
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff),
        ]
        return String(bytes: chars, encoding: .ascii) ?? ""
    }
}

// MARK: - Value decoding / encoding

enum SMCDecode {
    /// Decode an SMC payload into a Double using its 4-char data type.
    /// Supports the common numeric encodings: uiN, siN, flt, and the
    /// signed/unsigned fixed-point spXY / fpXY families (incl. fpe2).
    static func double(type: String, bytes: [UInt8]) -> Double? {
        guard !bytes.isEmpty else { return nil }
        let t = type.trimmingCharacters(in: CharacterSet(charactersIn: " \0"))

        switch t {
        case "ui8":
            return Double(bytes[0])
        case "ui16":
            return Double(be16(bytes))
        case "ui32":
            return Double(be32(bytes))
        case "si8":
            return Double(Int8(bitPattern: bytes[0]))
        case "si16":
            return Double(Int16(bitPattern: be16(bytes)))
        case "flt":
            guard bytes.count >= 4 else { return nil }
            let raw = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
            return Double(Float(bitPattern: raw))
        case "fpe2":
            // 14.2 unsigned fixed point: divide by 4.
            return Double(be16(bytes)) / 4.0
        default:
            // Generic signed fixed point "spXY": Y = fractional bit count (hex).
            if t.hasPrefix("sp"), t.count == 4, let frac = hexNibble(t, index: 3) {
                return Double(Int16(bitPattern: be16(bytes))) / Double(1 << frac)
            }
            // Generic unsigned fixed point "fpXY".
            if t.hasPrefix("fp"), t.count == 4, let frac = hexNibble(t, index: 3) {
                return Double(be16(bytes)) / Double(1 << frac)
            }
            return nil
        }
    }

    /// Encode an RPM/target into the byte layout expected for a given fan
    /// target data type ("flt" or "fpe2"). Returns nil for unsupported types.
    static func encodeFanTarget(_ rpm: Double, type: String) -> [UInt8]? {
        let t = type.trimmingCharacters(in: CharacterSet(charactersIn: " \0"))
        switch t {
        case "flt":
            let bits = Float(rpm).bitPattern
            return [UInt8(bits & 0xff), UInt8((bits >> 8) & 0xff), UInt8((bits >> 16) & 0xff), UInt8((bits >> 24) & 0xff)]
        case "fpe2":
            let v = UInt16(max(0, min(Double(UInt16.max), rpm * 4)))
            return [UInt8((v >> 8) & 0xff), UInt8(v & 0xff)]
        default:
            return nil
        }
    }

    private static func be16(_ b: [UInt8]) -> UInt16 {
        guard b.count >= 2 else { return b.first.map(UInt16.init) ?? 0 }
        return UInt16(b[0]) << 8 | UInt16(b[1])
    }

    private static func be32(_ b: [UInt8]) -> UInt32 {
        guard b.count >= 4 else { return 0 }
        return UInt32(b[0]) << 24 | UInt32(b[1]) << 16 | UInt32(b[2]) << 8 | UInt32(b[3])
    }

    private static func hexNibble(_ s: String, index: Int) -> Int? {
        let ch = Array(s)[index]
        return Int(String(ch), radix: 16)
    }
}
