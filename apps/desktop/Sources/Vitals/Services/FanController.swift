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
        Log.debug(.fan, "set fan \(fan) → manual \(rpm) rpm")
        update(fan: fan, command: FanCommand(fan: fan, mode: .manual, rpm: Double(rpm)))
    }

    func setAuto(fan: Int) {
        guard isInstalled else { return }
        Log.debug(.fan, "set fan \(fan) → automatic")
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
            Log.error(.fan, "couldn't save fan settings", error: error)
            lastError = "Couldn't save fan settings: \(error.localizedDescription)"
        }
    }

    // MARK: - Install / remove (one password each)

    func install() async {
        Log.notice(.fan, "installing fan-control helper")
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
            try await PrivilegedShell.runAsAdmin(script, prompt: "Vitals needs to install its fan-control helper.")
            // Seed an empty state file the user can write to from now on.
            if !FileManager.default.fileExists(atPath: FanControl.stateURL.path) {
                try? FanControl.writeCommands([])
            }
        }
        refreshInstalled()
    }

    func remove(fanCount: Int) async {
        Log.notice(.fan, "removing fan-control helper")
        // Restore automatic control before tearing the helper down.
        setAllAuto(fanCount: fanCount)
        try? await Task.sleep(for: .seconds(1))
        await runWorking {
            let script = """
            launchctl bootout system/\(FanControl.label) 2>/dev/null || true
            rm -f '\(FanControl.daemonPlistPath)'
            rm -f '\(FanControl.stateURL.path)'
            """
            try await PrivilegedShell.runAsAdmin(script, prompt: "Vitals needs to remove its fan-control helper.")
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
        } catch let error as PrivilegedShell.AdminError {
            if !error.cancelled {
                Log.error(.fan, "fan helper operation failed — \(error.message)")
                lastError = error.message
            }
        } catch {
            Log.error(.fan, "fan helper operation failed", error: error)
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

}
