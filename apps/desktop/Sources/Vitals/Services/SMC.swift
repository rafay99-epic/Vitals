import Foundation
import IOKit
import PrivateSensors

/// Client for the System Management Controller: reads fan state for the
/// dashboard, and writes fan mode/target for manual fan control. Reads work
/// for any user; writes require root (see `FanController`).
final class SMC {
    struct Fan: Identifiable {
        let id: Int
        let rpm: Double
        let minRPM: Double
        let maxRPM: Double
        let targetRPM: Double
        /// nil when the mode key is unavailable on this machine.
        let isManual: Bool?
    }

    struct SMCError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private let connection: io_connect_t

    /// A key's type and size never change, but fetching them costs a kernel
    /// round-trip — half the SMC traffic before this cache existed. Missing
    /// keys are remembered too, so absent keys (no F0Md on some machines)
    /// aren't re-queried every tick.
    private var keyInfoCache: [UInt32: SMCKeyInfoData] = [:]
    private var missingKeys: Set<UInt32> = []

    init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else {
            Log.noticeOnce(.smc, key: "smc-no-service", "AppleSMC service not found — fan readings and control are unavailable")
            return nil
        }
        defer { IOObjectRelease(service) }

        var conn: io_connect_t = 0
        let result = IOServiceOpen(service, mach_task_self_, 0, &conn)
        guard result == kIOReturnSuccess else {
            Log.noticeOnce(.smc, key: "smc-open-failed", "couldn't open the AppleSMC connection (IOServiceOpen \(result)) — no fan readings")
            return nil
        }
        connection = conn
    }

    deinit {
        IOServiceClose(connection)
    }

    // MARK: - Fans

    func fans() -> [Fan] {
        guard let count = read("FNum").map({ Int($0) }), count > 0 else { return [] }
        return (0..<min(count, 10)).compactMap { i in
            guard let rpm = read("F\(i)Ac") else { return nil }
            return Fan(
                id: i,
                rpm: rpm,
                minRPM: read("F\(i)Mn") ?? 0,
                maxRPM: read("F\(i)Mx") ?? 0,
                targetRPM: read("F\(i)Tg") ?? 0,
                isManual: read("F\(i)Md").map { $0 > 0.5 }
            )
        }
    }

    /// Forces the fan to a fixed rpm (clamped to its rated range).
    /// Returns the rpm actually applied. Requires root.
    func setFanTarget(_ fan: Int, rpm: Double) throws -> Double {
        let minRPM = read("F\(fan)Mn") ?? 0
        let maxRPM = read("F\(fan)Mx") ?? 0
        guard maxRPM > minRPM else {
            throw SMCError(message: "fan \(fan) has no usable speed range")
        }
        let clamped = min(max(rpm, minRPM), maxRPM)
        try enableManualMode(fan)
        try write("F\(fan)Tg", value: clamped)  // target rpm (float on Apple Silicon)
        return clamped
    }

    /// Returns the fan to macOS automatic control. Requires root.
    func setFanAutomatic(_ fan: Int) throws {
        try? write("F\(fan)Md", value: 0)  // auto
        try? write("Ftst", value: 0)       // clear the diagnostic unlock
    }

    /// Switches a fan to manual mode. On Apple Silicon M3/M4 the firmware
    /// holds fans in "system mode" (mode 3) and rejects a direct mode write;
    /// setting the `Ftst` diagnostic-unlock key first lets the mode change
    /// take. See agoodkind/macos-smc-fan for the reverse-engineering.
    private func enableManualMode(_ fan: Int) throws {
        let modeKey = "F\(fan)Md"
        // Fast path: already manual, or a direct write is accepted (Intel, M5).
        if (read(modeKey) ?? 0) == 1 { return }
        if (try? write(modeKey, value: 1)) != nil, (read(modeKey) ?? 0) == 1 { return }

        // Unlock path: set Ftst, then retry the mode write for a few seconds.
        try? write("Ftst", value: 1)
        for _ in 0..<60 {
            if (try? write(modeKey, value: 1)) != nil, (read(modeKey) ?? 0) == 1 { return }
            usleep(100_000)  // 100 ms
        }
        throw SMCError(message: "fan \(fan) stayed in system mode — firmware refused manual control")
    }

    // MARK: - Key access

    /// Reads a key and decodes it to a Double, or nil if the key is missing
    /// or has a type we don't understand.
    func read(_ key: String) -> Double? {
        guard let keyCode = Self.fourCC(key), let info = keyInfo(for: keyCode) else { return nil }

        var readInput = SMCParamStruct()
        readInput.key = keyCode
        readInput.keyInfo.dataSize = info.dataSize
        readInput.data8 = UInt8(VITALS_SMC_CMD_READ_KEY)
        guard let output = call(&readInput).output, output.result == 0 else { return nil }

        let bytes = withUnsafeBytes(of: output.bytes) { Array($0.prefix(Int(info.dataSize))) }
        return Self.decode(bytes, type: info.dataType)
    }

    private func keyInfo(for keyCode: UInt32) -> SMCKeyInfoData? {
        if let cached = keyInfoCache[keyCode] { return cached }
        guard !missingKeys.contains(keyCode) else { return nil }

        var input = SMCParamStruct()
        input.key = keyCode
        input.data8 = UInt8(VITALS_SMC_CMD_GET_KEY_INFO)
        guard let info = call(&input).output, info.result == 0, info.keyInfo.dataSize > 0 else {
            missingKeys.insert(keyCode)
            return nil
        }
        keyInfoCache[keyCode] = info.keyInfo
        return info.keyInfo
    }

    /// Encodes `value` for the key's native type and writes it. Requires root.
    private func write(_ key: String, value: Double) throws {
        guard let keyCode = Self.fourCC(key) else {
            throw SMCError(message: "invalid SMC key \(key)")
        }
        guard let info = keyInfo(for: keyCode) else {
            throw SMCError(message: "SMC key \(key) not available on this Mac")
        }

        let bytes = try Self.encode(value, type: info.dataType, size: Int(info.dataSize), key: key)
        var input = SMCParamStruct()
        input.key = keyCode
        input.keyInfo = info
        input.data8 = UInt8(VITALS_SMC_CMD_WRITE_KEY)
        withUnsafeMutableBytes(of: &input.bytes) { buffer in
            for (index, byte) in bytes.enumerated() { buffer[index] = byte }
        }

        let result = call(&input)
        if result.status == kIOReturnNotPrivileged {
            throw SMCError(message: "writing \(key) requires administrator rights")
        }
        guard result.status == kIOReturnSuccess, let output = result.output, output.result == 0 else {
            throw SMCError(message: "SMC rejected write to \(key) (result \(result.output?.result ?? 255))")
        }
    }

    private func call(_ input: inout SMCParamStruct) -> (status: kern_return_t, output: SMCParamStruct?) {
        var output = SMCParamStruct()
        var outputSize = MemoryLayout<SMCParamStruct>.stride
        let status = IOConnectCallStructMethod(
            connection,
            UInt32(VITALS_SMC_SELECTOR_YPC_EVENT),
            &input,
            MemoryLayout<SMCParamStruct>.stride,
            &output,
            &outputSize
        )
        return (status, status == kIOReturnSuccess ? output : nil)
    }

    // MARK: - Codecs

    private static func decode(_ bytes: [UInt8], type: UInt32) -> Double? {
        switch string(fromFourCC: type) {
        case "flt ":
            guard bytes.count >= 4 else { return nil }
            return Double(bytes.withUnsafeBytes { $0.load(as: Float32.self) })
        case "ui8 ":
            return bytes.first.map(Double.init)
        case "ui16":
            guard bytes.count >= 2 else { return nil }
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        case "ui32":
            guard bytes.count >= 4 else { return nil }
            return Double(bytes.prefix(4).reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
        case "sp78":
            guard bytes.count >= 2 else { return nil }
            return Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))) / 256.0
        case "fpe2":
            guard bytes.count >= 2 else { return nil }
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 4.0
        default:
            return nil
        }
    }

    private static func encode(_ value: Double, type: UInt32, size: Int, key: String) throws -> [UInt8] {
        switch string(fromFourCC: type) {
        case "flt ":
            return withUnsafeBytes(of: Float32(value)) { Array($0) }
        case "ui8 ":
            return [UInt8(min(max(value, 0), 255))]
        case "fpe2":
            let raw = UInt16(min(max(value, 0), 16383)) << 2
            return [UInt8(raw >> 8), UInt8(raw & 0xff)]
        default:
            throw SMCError(message: "unsupported data type for SMC key \(key)")
        }
    }

    private static func fourCC(_ key: String) -> UInt32? {
        let scalars = Array(key.unicodeScalars)
        guard scalars.count == 4, scalars.allSatisfy({ $0.isASCII }) else { return nil }
        return scalars.reduce(UInt32(0)) { $0 << 8 | UInt32($1.value) }
    }

    private static func string(fromFourCC code: UInt32) -> String {
        let chars = (0..<4).reversed().map { Character(UnicodeScalar(UInt8(code >> ($0 * 8) & 0xff))) }
        return String(chars)
    }
}
