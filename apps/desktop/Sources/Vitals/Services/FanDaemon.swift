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

/// Set by the SIGTERM handler and checked by the run loop. Signal handlers
/// may only touch async-signal-safe state — no allocation, no IOKit — so
/// the handler just raises this flag and the loop does the cleanup.
private var daemonShouldExit: sig_atomic_t = 0

/// The privileged side: `Vitals --fan-daemon`, launched as root by launchd.
/// It re-applies the desired fan state on a loop so manual targets survive
/// sleep/wake (which resets the SMC unlock) and firmware mitigation.
enum FanDaemon {
    static func run() -> Never {
        signal(SIGTERM) { _ in daemonShouldExit = 1 }

        // One SMC connection for the daemon's lifetime, retried only while
        // opening fails — not a fresh open/close every cycle.
        var smc: SMC?
        while daemonShouldExit == 0 {
            if smc == nil { smc = SMC() }
            if let smc { apply(using: smc) }
            // Sleep in short slices so SIGTERM is honored promptly.
            for _ in 0..<10 where daemonShouldExit == 0 {
                Thread.sleep(forTimeInterval: 0.3)
            }
        }

        // Hand fans back to macOS before the daemon exits.
        if let smc = smc ?? SMC() {
            for command in FanControl.loadCommands() {
                try? smc.setFanAutomatic(command.fan)
            }
        }
        exit(0)
    }

    private static func apply(using smc: SMC) {
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
