import Foundation

/// One fan's desired state, shared between the GUI (writer) and the daemon
/// (applier) through a JSON file.
struct FanCommand: Codable {
    enum Mode: String, Codable { case auto, manual }
    let fan: Int
    let mode: Mode
    let rpm: Double
}

/// Filesystem contract between the app and its privileged helper.
enum FanControl {
    static let label = "com.tudotechlab.vitals.fand"
    static let supportDir = URL(fileURLWithPath: "/Library/Application Support/Vitals", isDirectory: true)
    static let stateURL = supportDir.appendingPathComponent("fan-state.json")
    static let daemonPlistPath = "/Library/LaunchDaemons/\(label).plist"

    static func loadCommands() -> [FanCommand] {
        guard let data = try? Data(contentsOf: stateURL),
              let commands = try? JSONDecoder().decode([FanCommand].self, from: data)
        else { return [] }
        return commands
    }

    static func writeCommands(_ commands: [FanCommand]) throws {
        let data = try JSONEncoder().encode(commands)
        try data.write(to: stateURL, options: .atomic)
    }
}

/// The privileged side: `Vitals --fan-daemon`, launched as root by launchd.
/// It re-applies the desired fan state on a loop so manual targets survive
/// sleep/wake (which resets the SMC unlock) and firmware mitigation.
enum FanDaemon {
    static func run() -> Never {
        signal(SIGTERM) { _ in
            // Hand fans back to macOS before the daemon exits.
            if let smc = SMC() {
                for command in FanControl.loadCommands() {
                    try? smc.setFanAutomatic(command.fan)
                }
            }
            exit(0)
        }

        while true {
            apply()
            Thread.sleep(forTimeInterval: 3)
        }
    }

    private static func apply() {
        guard let smc = SMC() else { return }
        for command in FanControl.loadCommands() {
            switch command.mode {
            case .manual:
                _ = try? smc.setFanTarget(command.fan, rpm: command.rpm)
            case .auto:
                try? smc.setFanAutomatic(command.fan)
            }
        }
    }
}
