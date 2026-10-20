import Foundation

enum Emulators {
    static func list() -> [WireEmulator] {
        android() + ios()
    }

    static func stop(kind: String, id: String) -> String? {
        switch kind {
        case "android":
            guard id.hasPrefix("emulator-"), let adb = adbPath else { return "Not an Android emulator" }
            return SystemPower.run(adb, ["-s", id, "emu", "kill"])
        case "ios":
            guard UUID(uuidString: id) != nil else { return "Not a simulator id" }
            return SystemPower.run("/usr/bin/xcrun", ["simctl", "shutdown", id])
        default:
            return "Unknown emulator kind"
        }
    }

    private static var adbPath: String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            ProcessInfo.processInfo.environment["ANDROID_HOME"].map { "\($0)/platform-tools/adb" },
            "\(home)/Library/Android/sdk/platform-tools/adb",
            "/opt/homebrew/bin/adb",
        ]
        return candidates.compactMap { $0 }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func android() -> [WireEmulator] {
        guard let adb = adbPath, let output = capture(adb, ["devices"]) else { return [] }
        return output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\t")
            guard parts.count == 2, parts[0].hasPrefix("emulator-"), parts[1] == "device" else { return nil }
            let id = String(parts[0])
            let name = capture(adb, ["-s", id, "emu", "avd", "name"])?
                .split(whereSeparator: \.isNewline).first.map(String.init)?
                .trimmingCharacters(in: .whitespaces)
            return WireEmulator(kind: "android", id: id, name: name ?? id, pid: nil)
        }
    }

    private struct SimctlList: Decodable {
        struct Device: Decodable {
            let udid: String
            let name: String
            let state: String
        }
        let devices: [String: [Device]]
    }

    private static func ios() -> [WireEmulator] {
        guard let output = capture("/usr/bin/xcrun", ["simctl", "list", "devices", "booted", "-j"]),
              let list = try? JSONDecoder().decode(SimctlList.self, from: Data(output.utf8))
        else { return [] }
        return list.devices.values.flatMap { $0 }
            .filter { $0.state == "Booted" }
            .map { WireEmulator(kind: "ios", id: $0.udid, name: $0.name, pid: nil) }
    }

    private static func capture(_ executable: String, _ arguments: [String]) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
    }
}
