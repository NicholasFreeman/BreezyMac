//
//  SMCConnection.swift
//  BreezyMac — Shared
//
//  Thin, resident IOKit AppleSMC user-client. Opens one connection and keeps
//  it for the lifetime of the owner (the app for reads, the helper for writes),
//  rather than the reference project's fork-per-command model.
//
//  Reads never require root. Writes (fan mode / target) require root and are
//  only performed by the privileged helper — see Helper/FanSMC.swift.
//

import Foundation
import IOKit

final class SMCConnection {
    enum SMCError: Error, CustomStringConvertible {
        case notOpen
        case serviceNotFound
        case openFailed(kern_return_t)
        case keyNotFound(String)
        case callFailed(kern_return_t)
        case writeRejected(UInt8)   // non-zero result byte

        var description: String {
            switch self {
            case .notOpen: return "SMC connection is not open"
            case .serviceNotFound: return "AppleSMC service not found"
            case .openFailed(let r): return "IOServiceOpen failed (0x\(String(r, radix: 16)))"
            case .keyNotFound(let k): return "SMC key not found: \(k)"
            case .callFailed(let r): return "SMC call failed (0x\(String(r, radix: 16)))"
            case .writeRejected(let r): return "SMC write rejected (result 0x\(String(r, radix: 16)))"
            }
        }
    }

    private var connection: io_connect_t = 0
    var isOpen: Bool { connection != 0 }

    // MARK: Lifecycle

    func open() throws {
        guard connection == 0 else { return }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { throw SMCError.serviceNotFound }
        defer { IOObjectRelease(service) }

        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard result == kIOReturnSuccess else {
            connection = 0
            throw SMCError.openFailed(result)
        }
    }

    func close() {
        if connection != 0 {
            IOServiceClose(connection)
            connection = 0
        }
    }

    deinit { close() }

    // MARK: Raw call

    private func call(_ selector: SMCSelector, _ input: inout SMCKeyData, _ output: inout SMCKeyData) throws {
        guard connection != 0 else { throw SMCError.notOpen }
        input.data8 = selector.rawValue
        let inputSize = MemoryLayout<SMCKeyData>.stride
        var outputSize = MemoryLayout<SMCKeyData>.stride
        let result = IOConnectCallStructMethod(connection, kSMCKernelIndex, &input, inputSize, &output, &outputSize)
        guard result == kIOReturnSuccess else { throw SMCError.callFailed(result) }
    }

    private func keyInfo(_ key: String) throws -> SMCKeyInfoData {
        var input = SMCKeyData()
        var output = SMCKeyData()
        input.key = FourCC.from(key)
        try call(.readKeyInfo, &input, &output)
        guard output.keyInfo.dataSize > 0 else { throw SMCError.keyNotFound(key) }
        return output.keyInfo
    }

    // MARK: Read

    /// Read a key's raw value (data type + bytes). Returns nil if the key is
    /// absent on this hardware (a normal condition when probing sensor lists).
    func read(_ key: String) -> SMCValue? {
        guard connection != 0 else { return nil }
        guard let info = try? keyInfo(key) else { return nil }

        var input = SMCKeyData()
        var output = SMCKeyData()
        input.key = FourCC.from(key)
        input.keyInfo.dataSize = info.dataSize
        guard (try? call(.readBytes, &input, &output)) != nil else { return nil }

        let size = Int(min(info.dataSize, 32))
        var bytes = [UInt8](repeating: 0, count: size)
        withUnsafeBytes(of: output.bytes) { raw in
            for i in 0..<size { bytes[i] = raw[i] }
        }
        return SMCValue(key: key,
                        dataSize: info.dataSize,
                        dataType: FourCC.toString(info.dataType),
                        bytes: bytes)
    }

    /// Convenience: read a numeric key as a Double.
    func readDouble(_ key: String) -> Double? {
        guard let value = read(key) else { return nil }
        return SMCDecode.double(type: value.dataType, bytes: value.bytes)
    }

    // MARK: Key enumeration

    /// Number of keys the SMC exposes (`#KEY`), used to walk the key table.
    func keyCount() -> Int {
        guard let v = readDouble("#KEY"), v > 0 else { return 0 }
        return Int(v)
    }

    /// The 4-char key at a table index (SMC read-by-index sub-command).
    func key(at index: Int) -> String? {
        guard connection != 0 else { return nil }
        var input = SMCKeyData()
        var output = SMCKeyData()
        input.data32 = UInt32(index)
        guard (try? call(.readIndex, &input, &output)) != nil, output.key != 0 else { return nil }
        return FourCC.toString(output.key)
    }

    /// Enumerate every key the SMC exposes. Used once to discover the full set of
    /// temperature sensors present on this specific machine.
    func allKeys() -> [String] {
        let count = keyCount()
        guard count > 0, count < 100_000 else { return [] }
        var keys: [String] = []
        keys.reserveCapacity(count)
        for i in 0..<count {
            if let k = key(at: i) { keys.append(k) }
        }
        return keys
    }

    // MARK: Write (root only)

    /// Write raw bytes to a key. `keyType` may be supplied to skip a keyInfo
    /// round-trip; otherwise it is looked up.
    func write(_ key: String, bytes: [UInt8]) throws {
        guard connection != 0 else { throw SMCError.notOpen }
        let info = try keyInfo(key)

        var input = SMCKeyData()
        var output = SMCKeyData()
        input.key = FourCC.from(key)
        input.keyInfo.dataSize = info.dataSize
        withUnsafeMutableBytes(of: &input.bytes) { raw in
            for i in 0..<min(bytes.count, 32) { raw[i] = bytes[i] }
        }
        try call(.writeBytes, &input, &output)
        guard output.result == 0 else { throw SMCError.writeRejected(output.result) }
    }
}
