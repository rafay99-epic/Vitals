import Foundation
import AppKit

/// GUI side of fan control. Installing the privileged helper takes one
/// administrator prompt; after that, changing fan speed just rewrites the
/// shared state file (no password) and the root daemon applies it.
@MainActor
final class FanController: ObservableObject {
    @Published private(set) var isInstalled = false
    @Published private(set) var isWorking = false
    @Published private(set) var lastError: String?
    @Published private(set) var commands: [FanCommand] = []

    init() {
        refreshInstalled()
        commands = FanControl.loadCommands()
    }

    func refreshInstalled() {
        isInstalled = FileManager.default.fileExists(atPath: FanControl.daemonPlistPath)
    }

    func target(for fan: Int) -> FanCommand? {
        commands.first { $0.fan == fan }
    }

    // MARK: - Control (no password once installed)

    func setTarget(fan: Int, rpm: Int) {
        guard isInstalled else { return }
        update(fan: fan, command: FanCommand(fan: fan, mode: .manual, rpm: Double(rpm)))
    }

    func setAuto(fan: Int) {
        guard isInstalled else { return }
        update(fan: fan, command: FanCommand(fan: fan, mode: .auto, rpm: 0))
    }

    func setAllAuto(fanCount: Int) {
        guard isInstalled else { return }
        commands = (0..<fanCount).map { FanCommand(fan: $0, mode: .auto, rpm: 0) }
        persist()
    }

    private func update(fan: Int, command: FanCommand) {
        commands.removeAll { $0.fan == fan }
        commands.append(command)
        commands.sort { $0.fan < $1.fan }
        persist()
    }

    private func persist() {
        do {
            try FanControl.writeCommands(commands)
            lastError = nil
        } catch {
            lastError = "Couldn't save fan settings: \(error.localizedDescription)"
        }
    }

    // MARK: - Install / remove (one password each)

    func install() async {
        guard let executable = Bundle.main.executableURL?.path else {
            lastError = "Could not locate the Vitals executable."
            return
        }
        await runWorking {
            let plist = Self.daemonPlist(executablePath: executable)
            let plistTemp = NSTemporaryDirectory() + "\(FanControl.label).plist"
            try plist.write(toFile: plistTemp, atomically: true, encoding: .utf8)

            let script = """
            set -e
            mkdir -p '\(FanControl.supportDir.path)'
            chown '\(NSUserName())' '\(FanControl.supportDir.path)'
            chmod 755 '\(FanControl.supportDir.path)'
            cp '\(plistTemp)' '\(FanControl.daemonPlistPath)'
            chown root:wheel '\(FanControl.daemonPlistPath)'
            chmod 644 '\(FanControl.daemonPlistPath)'
            launchctl bootout system/\(FanControl.label) 2>/dev/null || true
            launchctl bootstrap system '\(FanControl.daemonPlistPath)'
            """
            try await Self.runAsAdmin(script, prompt: "Vitals needs to install its fan-control helper.")
            // Seed an empty state file the user can write to from now on.
            if !FileManager.default.fileExists(atPath: FanControl.stateURL.path) {
                try? FanControl.writeCommands([])
            }
        }
        refreshInstalled()
    }

    func remove(fanCount: Int) async {
        // Restore automatic control before tearing the helper down.
        setAllAuto(fanCount: fanCount)
        try? await Task.sleep(for: .seconds(1))
        await runWorking {
            let script = """
            launchctl bootout system/\(FanControl.label) 2>/dev/null || true
            rm -f '\(FanControl.daemonPlistPath)'
            rm -f '\(FanControl.stateURL.path)'
            """
            try await Self.runAsAdmin(script, prompt: "Vitals needs to remove its fan-control helper.")
        }
        commands = []
        refreshInstalled()
    }

    private func runWorking(_ body: () async throws -> Void) async {
        guard !isWorking else { return }
        isWorking = true
        lastError = nil
        defer { isWorking = false }
        do {
            try await body()
        } catch let error as AdminError {
            if !error.cancelled { lastError = error.message }
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - launchd plist

    private static func daemonPlist(executablePath: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        	<key>Label</key>
        	<string>\(FanControl.label)</string>
        	<key>ProgramArguments</key>
        	<array>
        		<string>\(executablePath)</string>
        		<string>--fan-daemon</string>
        	</array>
        	<key>RunAtLoad</key>
        	<true/>
        	<key>KeepAlive</key>
        	<true/>
        	<key>ThrottleInterval</key>
        	<integer>5</integer>
        </dict>
        </plist>
        """
    }

    // MARK: - Privileged execution

    private struct AdminError: Error {
        let message: String
        let cancelled: Bool
    }

    nonisolated private static func runAsAdmin(_ shellScript: String, prompt: String) async throws {
        // Stage the shell script to a temp file so the AppleScript string
        // stays a single, safely-escaped command.
        let scriptPath = NSTemporaryDirectory() + "vitals-fan-\(UUID().uuidString).sh"
        try shellScript.write(toFile: scriptPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: scriptPath) }

        let appleScript = "do shell script \"/bin/sh '\(scriptPath)'\" with administrator privileges with prompt \"\(prompt)\""

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = ["-e", appleScript]
                let stderr = Pipe()
                process.standardOutput = Pipe()
                process.standardError = stderr
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: AdminError(message: error.localizedDescription, cancelled: false))
                    return
                }
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    continuation.resume()
                    return
                }
                let output = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let cancelled = output.contains("-128")
                let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(throwing: AdminError(
                    message: trimmed.isEmpty ? "Helper command failed." : trimmed,
                    cancelled: cancelled
                ))
            }
        }
    }
}
