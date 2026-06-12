import Foundation
import IOKit
import PrivateSensors

/// Read-only client for the System Management Controller.
/// Used for fan speeds; temperatures come from `HIDSensors`.
final class SMC {
    struct Fan: Identifiable {
        let id: Int
        let rpm: Double
        let minRPM: Double
        let maxRPM: Double
        let targetRPM: Double
    }

    private let connection: io_connect_t

    init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var conn: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, 0, &conn) == kIOReturnSuccess else { return nil }
        connection = conn
    }

    deinit {
        IOServiceClose(connection)
    }

    func fans() -> [Fan] {
        guard let count = read("FNum").map({ Int($0) }), count > 0 else { return [] }
        return (0..<min(count, 10)).compactMap { i in
            guard let rpm = read("F\(i)Ac") else { return nil }
            return Fan(
                id: i,
                rpm: rpm,
                minRPM: read("F\(i)Mn") ?? 0,
                maxRPM: read("F\(i)Mx") ?? 0,
                targetRPM: read("F\(i)Tg") ?? 0
            )
        }
    }

    /// Reads a key and decodes it to a Double, or nil if the key is missing
    /// or has a type we don't understand.
    func read(_ key: String) -> Double? {
        guard let keyCode = Self.fourCC(key) else { return nil }

        var input = SMCParamStruct()
        input.key = keyCode
        input.data8 = UInt8(VITALS_SMC_CMD_GET_KEY_INFO)
        guard let info = call(&input), info.result == 0, info.keyInfo.dataSize > 0 else { return nil }

        var readInput = SMCParamStruct()
        readInput.key = keyCode
        readInput.keyInfo.dataSize = info.keyInfo.dataSize
        readInput.data8 = UInt8(VITALS_SMC_CMD_READ_KEY)
        guard let output = call(&readInput), output.result == 0 else { return nil }

        let bytes = withUnsafeBytes(of: output.bytes) { Array($0.prefix(Int(info.keyInfo.dataSize))) }
        return Self.decode(bytes, type: info.keyInfo.dataType)
    }

    private func call(_ input: inout SMCParamStruct) -> SMCParamStruct? {
        var output = SMCParamStruct()
        var outputSize = MemoryLayout<SMCParamStruct>.stride
        let result = IOConnectCallStructMethod(
            connection,
            UInt32(VITALS_SMC_SELECTOR_YPC_EVENT),
            &input,
            MemoryLayout<SMCParamStruct>.stride,
            &output,
            &outputSize
        )
        return result == kIOReturnSuccess ? output : nil
    }

    private static func decode(_ bytes: [UInt8], type: UInt32) -> Double? {
        let typeName = string(fromFourCC: type)
        switch typeName {
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
