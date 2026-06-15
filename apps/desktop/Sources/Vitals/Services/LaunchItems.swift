import Foundation

/// One thing that launches itself — a per-user login agent, a system-wide agent,
/// or a root daemon. Discovered by reading the launchd plist directories (all
/// world-readable), so this is pure read-freely; only the user's own non-Apple
/// agents may be toggled, and that's reversible.
struct LaunchItem: Identifiable, Equatable {
    enum Kind: String {
        case userAgent, systemAgent, systemDaemon

        var typeLabel: String {
            switch self {
            case .userAgent:   return "Login agent"
            case .systemAgent: return "System agent"
            case .systemDaemon: return "System daemon"
            }
        }
        var domain: String { self == .userAgent ? "You" : "System" }
    }

    let label: String
    let program: String?
    let plistPath: URL
    let kind: Kind
    let runAtLoad: Bool
    var disabled: Bool

    var id: String { plistPath.path }
    var isApple: Bool { label.hasPrefix("com.apple.") }

    /// Friendly name from the program's `.app`, else the launchd label.
    var displayName: String {
        if let program, let app = program.split(separator: "/").first(where: { $0.hasSuffix(".app") }) {
            return String(app.dropLast(4))
        }
        return label
    }

    /// Only the user's own non-Apple login agents are toggled here: it's
    /// root-free and reversible (`launchctl enable`/`disable`). System and Apple
    /// items are shown read-only — disabling those needs admin and risks the OS,
    /// which the safety rules keep off-limits.
    var canToggle: Bool { kind == .userAgent && !isApple }
}

/// Reads the launchd plist directories and toggles user agents via `launchctl`.
/// All blocking (file + process), so callers run it off the main thread.
enum LaunchItemScanner {
    static func scan() -> [LaunchItem] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var items = parseDir(home.appendingPathComponent("Library/LaunchAgents"), kind: .userAgent)
        items += parseDir(URL(fileURLWithPath: "/Library/LaunchAgents"), kind: .systemAgent)
        items += parseDir(URL(fileURLWithPath: "/Library/LaunchDaemons"), kind: .systemDaemon)

        // The persistent enable/disable override is authoritative for user agents.
        let disabled = disabledLabels()
        for index in items.indices where items[index].kind == .userAgent {
            items[index].disabled = disabled.contains(items[index].label)
        }
        // Third-party first (what the user can act on), then Apple's, alphabetical.
        return items.sorted {
            ($0.isApple ? 1 : 0, $0.displayName.localizedLowercase) < ($1.isApple ? 1 : 0, $1.displayName.localizedLowercase)
        }
    }

    /// Enables/disables a user login agent. Disabling also stops it now
    /// (best-effort `bootout`); enabling takes effect at next login. Reversible.
    static func setDisabled(_ disabled: Bool, item: LaunchItem) {
        guard item.canToggle else { return }
        let target = "gui/\(getuid())/\(item.label)"
        run("/bin/launchctl", [disabled ? "disable" : "enable", target])
        if disabled {
            run("/bin/launchctl", ["bootout", target])
        }
    }

    private static func parseDir(_ dir: URL, kind: LaunchItem.Kind) -> [LaunchItem] {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
        return urls.filter { $0.pathExtension == "plist" }.compactMap { parse($0, kind: kind) }
    }

    private static func parse(_ url: URL, kind: LaunchItem.Kind) -> LaunchItem? {
        guard let data = try? Data(contentsOf: url),
              let plist = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
              let label = plist["Label"] as? String
        else { return nil }
        let program = (plist["Program"] as? String) ?? (plist["ProgramArguments"] as? [String])?.first
        return LaunchItem(
            label: label,
            program: program,
            plistPath: url,
            kind: kind,
            runAtLoad: (plist["RunAtLoad"] as? Bool) ?? false,
            disabled: (plist["Disabled"] as? Bool) ?? false
        )
    }

    /// Labels the user has persistently disabled, from `launchctl print-disabled`
    /// (lines like `"label" => disabled`).
    private static func disabledLabels() -> Set<String> {
        var set: Set<String> = []
        for line in run("/bin/launchctl", ["print-disabled", "gui/\(getuid())"]).split(separator: "\n") {
            guard line.contains("=> disabled") else { continue }
            let quoted = line.split(separator: "\"")
            if quoted.count >= 2 { set.insert(String(quoted[1])) }
        }
        return set
    }

    @discardableResult
    private static func run(_ launchPath: String, _ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
}
