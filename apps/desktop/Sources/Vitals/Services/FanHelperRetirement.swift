import Foundation

/// Fan control was removed. Older builds installed a root launchd helper
/// (`<bundle id>.fand`, KeepAlive) that runs this binary with `--fan-daemon`
/// and applies `fan-state.json` every few seconds. Both sides retire it:
/// - the app, on launch, rewrites a leftover state file to "every fan on
///   automatic", so a still-running old helper hands the fans back to macOS
///   (the file is user-owned, so no password);
/// - the helper, the next time launchd starts it on this binary, restores
///   automatic control, deletes its plist and state, and unloads itself.
enum FanHelperRetirement {
    private struct Command: Encodable {
        let fan: Int
        let mode = "auto"
        let rpm = 0.0
    }

    private static let label = (Bundle.main.bundleIdentifier ?? "com.syntaxlabtechnology.vitals") + ".fand"
    private static let supportDir = "/Library/Application Support/\(Channel.current.displayName)"
    private static let statePath = supportDir + "/fan-state.json"
    private static let plistPath = "/Library/LaunchDaemons/\(label).plist"

    /// App side. No-op unless an old helper left its state file behind.
    static func releaseFans() {
        guard FileManager.default.fileExists(atPath: statePath), let smc = SMC() else { return }
        let fans = smc.fans().map(\.id)
        do {
            try autoState(for: fans).write(to: URL(fileURLWithPath: statePath), options: .atomic)
            Log.notice(.fan, "released \(fans.count) fans to automatic control (fan control was removed)")
        } catch {
            Log.error(.fan, "couldn't reset the retired fan helper's state", error: error)
        }
    }

    /// The state file telling an old helper to put every fan on automatic. Its
    /// shape is the old helper's decoding contract: `[{fan, mode, rpm}]`.
    static func autoState(for fans: [Int]) throws -> Data {
        try JSONEncoder().encode(fans.map { Command(fan: $0) })
    }

    /// Root side: `Vitals --fan-daemon`, started by the old launchd job.
    static func runAsHelper() -> Never {
        if let smc = SMC() {
            for fan in smc.fans() { smc.setFanAutomatic(fan.id) }
        }
        try? FileManager.default.removeItem(atPath: plistPath)
        try? FileManager.default.removeItem(atPath: statePath)
        rmdir(supportDir)   // only succeeds when empty
        // Unload the job so KeepAlive doesn't respawn us. This SIGTERMs us too.
        let launchctl = Process()
        launchctl.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        launchctl.arguments = ["bootout", "system/\(label)"]
        if (try? launchctl.run()) != nil { launchctl.waitUntilExit() }
        exit(0)
    }
}
