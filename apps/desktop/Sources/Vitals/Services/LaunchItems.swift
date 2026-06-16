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

    /// Apple's own items are never modified (safety rule); everything else can
    /// be disabled or removed.
    var isActionable: Bool { !isApple }

    /// Disabling needs an admin prompt only for system daemons (the `system`
    /// domain). User *and* system agents load per-user, so they use the
    /// no-password `gui` override.
    var disableNeedsAdmin: Bool { kind == .systemDaemon }

    /// Removing your own agent just trashes its plist (recoverable, no password).
    /// Anything in `/Library` is root-owned, so removing it needs admin.
    var removeNeedsAdmin: Bool { kind != .userAgent }
}

/// Reads the launchd plist directories and toggles user agents via `launchctl`.
/// All blocking (file + process), so callers run it off the main thread.
enum LaunchItemScanner {
    static func scan() -> [LaunchItem] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var items = parseDir(home.appendingPathComponent("Library/LaunchAgents"), kind: .userAgent)
        items += parseDir(URL(fileURLWithPath: "/Library/LaunchAgents"), kind: .systemAgent)
        items += parseDir(URL(fileURLWithPath: "/Library/LaunchDaemons"), kind: .systemDaemon)

        // Never list or touch Vitals itself or its own helpers (safety rule) —
        // both the Stable and Dev namespaces, and anything launching from a
        // Vitals app bundle.
        items.removeAll { item in
            item.label.hasPrefix("com.syntaxlabtechnology.vitals")
                || (item.program?.contains("/Vitals.app/") ?? false)
                || (item.program?.contains("/Vitals Dev.app/") ?? false)
        }

        // Reflect the persistent enable/disable override when present (it wins
        // over the plist's own `Disabled` key, which `parse` already read);
        // otherwise keep the plist value. Agents (user + system) live in the
        // per-user gui domain, daemons in the system domain — both readable
        // without root.
        let guiOverride = overrideStates(domain: "gui/\(getuid())")
        let systemOverride = overrideStates(domain: "system")
        for index in items.indices {
            let override = items[index].kind == .systemDaemon ? systemOverride : guiOverride
            if let disabled = override[items[index].label] {
                items[index].disabled = disabled
            }
        }
        // Third-party first (what the user can act on), then Apple's, alphabetical.
        return items.sorted {
            ($0.isApple ? 1 : 0, $0.displayName.localizedLowercase) < ($1.isApple ? 1 : 0, $1.displayName.localizedLowercase)
        }
    }

    /// What an admin script does (built by `adminScript`).
    enum AdminAction { case disable(Bool), remove }

    /// Enables/disables an agent via the per-user `gui` override (no root) — for
    /// user and system agents. Disabling also stops it now. Reversible.
    static func directDisable(_ disabled: Bool, item: LaunchItem) {
        guard item.isActionable, !item.disableNeedsAdmin else { return }
        let target = "gui/\(getuid())/\(item.label)"
        run("/bin/launchctl", [disabled ? "disable" : "enable", target])
        if disabled { run("/bin/launchctl", ["bootout", target]) }
    }

    /// Removes your own agent by stopping it and moving its plist to the Trash
    /// (recoverable). User-domain only — no root. Returns true on success.
    static func trashUserAgent(item: LaunchItem) -> Bool {
        guard item.kind == .userAgent, item.isActionable else { return false }
        run("/bin/launchctl", ["bootout", "gui/\(getuid())/\(item.label)"])
        do {
            try FileManager.default.trashItem(at: item.plistPath, resultingItemURL: nil)
            return true
        } catch {
            Log.error(.app, "couldn't trash login item \(item.plistPath.lastPathComponent)", error: error)
            return false
        }
    }

    /// Builds a root script for a system-domain disable/remove, re-validating the
    /// label and (for removal) the plist path against the same allowlist the app
    /// uses everywhere it escalates — absolute, no `..`/quotes, never `/System`,
    /// never `com.apple.*`, confined to the launchd dirs. Returns nil (no script)
    /// if anything fails validation, so an unsafe action simply can't run.
    static func adminScript(for action: AdminAction, item: LaunchItem) -> (script: String, prompt: String)? {
        guard item.isActionable, isSafeLabel(item.label) else { return nil }
        switch action {
        case .disable(let disabled):
            guard item.kind == .systemDaemon else { return nil }
            let verb = disabled ? "disable" : "enable"
            var script = "#!/bin/sh\n/bin/launchctl \(verb) system/\(item.label)\n"
            if disabled { script += "/bin/launchctl bootout system/\(item.label) 2>/dev/null || true\n" }
            return (script, "Vitals needs administrator access to \(verb) the system daemon “\(item.label)”.")
        case .remove:
            guard item.kind != .userAgent, let safePath = safeSystemPlistPath(item.plistPath) else { return nil }
            let domain = item.kind == .systemDaemon ? "system" : "gui/\(getuid())"
            let script = "#!/bin/sh\n"
                + "/bin/launchctl bootout \(domain)/\(item.label) 2>/dev/null || true\n"
                + "rm -f '\(safePath)' 2>/dev/null || true\n"
            return (script, "Vitals needs administrator access to remove the launch item “\(item.label)”.")
        }
    }

    /// Labels go straight into a root shell command, so allow only launchd's own
    /// safe character set — no spaces, quotes, slashes or shell metacharacters.
    private static func isSafeLabel(_ label: String) -> Bool {
        !label.isEmpty && label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_" }
    }

    /// The validated absolute path for a system launchd plist, or nil if it fails
    /// any check. Mirrors `AppUninstaller.systemRemovalScript`.
    private static func safeSystemPlistPath(_ url: URL) -> String? {
        let path = url.standardizedFileURL.path
        guard path.hasPrefix("/"), path != "/", !path.contains(".."), !path.contains("'"),
              !path.hasPrefix("/System"), url.pathExtension == "plist",
              !url.lastPathComponent.hasPrefix("com.apple.")
        else { return nil }
        let roots = ["/Library/LaunchAgents/", "/Library/LaunchDaemons/"]
        return roots.contains { path.hasPrefix($0) } ? path : nil
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

    /// Explicit enable/disable overrides in `domain` (`label → isDisabled`), from
    /// `launchctl print-disabled` (lines like `"label" => disabled` / `=> enabled`).
    /// A label absent from the map has no override. Works without root for both
    /// the gui and system domains.
    static func overrideStates(domain: String) -> [String: Bool] {
        parseOverrides(run("/bin/launchctl", ["print-disabled", domain]))
    }

    /// Parses `launchctl print-disabled` output (`"label" => disabled|enabled`)
    /// into `label → isDisabled`. Pure, for testing.
    static func parseOverrides(_ text: String) -> [String: Bool] {
        var map: [String: Bool] = [:]
        for line in text.split(separator: "\n") {
            let quoted = line.split(separator: "\"")
            guard quoted.count >= 2 else { continue }
            if line.contains("=> disabled") { map[String(quoted[1])] = true }
            else if line.contains("=> enabled") { map[String(quoted[1])] = false }
        }
        return map
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
            Log.debug(.app, "login-items helper process failed to run", error: error)
            return ""
        }
    }
}
