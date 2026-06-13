import Foundation

/// A file or folder an app left behind outside its bundle.
struct Leftover: Identifiable, Hashable {
    /// Where the leftover lives — decides how it's removed.
    enum Domain { case user, system }

    enum Category: String, CaseIterable {
        case appSupport = "Application Support"
        case caches = "Caches"
        case preferences = "Preferences"
        case logs = "Logs"
        case crashReports = "Crash Reports"
        case savedState = "Saved State"
        case containers = "Containers"
        case webData = "Web & Cookies"
        case launchAgents = "Launch Agents"
        case scripts = "Application Scripts"
        case plugins = "Plug-ins & Extensions"
        case helperTools = "Helper Tools"
        case receipts = "Receipts"
        case shared = "Shared Data"
    }

    let id: URL
    let category: Category
    let domain: Domain
    var sizeBytes: UInt64

    /// System-domain leftovers are owned by root, so removal needs admin and
    /// can't go to the Trash — it's a permanent delete.
    var requiresAdmin: Bool { domain == .system }
}

/// Locates everything an app leaves behind — the per-user files under
/// `~/Library` (removed to the Trash) and the system-level files under
/// `/Library` and friends (removed with administrator rights). Also detects a
/// Homebrew cask install and orphaned system extensions.
///
/// The catalog of locations and the safety-first, age-/identity-gated design
/// are informed by the Mole project (https://github.com/tw93/mole, GPL-3.0) —
/// full credit to its authors. Vitals is likewise GPL-3.0; see LICENSE.
///
/// Identity gating is strict: bundle ids must validate as reverse-DNS before
/// they're used to build any path, system-level name matches require a
/// distinctive (≥5 char, non-generic) name, and `/System` and `com.apple.*`
/// are never returned.
enum LeftoverScanner {
    // MARK: Identity helpers

    /// Apps name folders inconsistently ("My App", "MyApp", "my-app") and ship
    /// channel suffixes ("Zed Nightly"), so probe every common variant plus the
    /// base name with the suffix stripped. Names under 2 characters are
    /// rejected — they'd match far too broadly.
    static func nameVariants(_ name: String) -> [String] {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return [] }

        var bases = [trimmed]
        let suffixes = ["Nightly", "Beta", "Alpha", "Dev", "Canary", "Preview",
                        "Insider", "Stable", "Release", "RC", "LTS",
                        "Developer Edition", "Technology Preview"]
        for suffix in suffixes where trimmed.hasSuffix(" \(suffix)") {
            let base = String(trimmed.dropLast(suffix.count + 1)).trimmingCharacters(in: .whitespaces)
            if base.count >= 2 { bases.append(base) }
        }

        var variants: [String] = []
        for base in bases {
            variants += [
                base,
                base.replacingOccurrences(of: " ", with: ""),
                base.replacingOccurrences(of: " ", with: "-"),
                base.replacingOccurrences(of: " ", with: "_"),
            ]
        }
        variants += variants.map { $0.lowercased() }

        var unique: [String] = []
        for variant in variants where !unique.contains(variant) && variant.count >= 2 {
            unique.append(variant)
        }
        return unique
    }

    /// Only reverse-DNS-looking identifiers may build paths — a malformed
    /// Info.plist must not inject globs or traversal.
    static func isValidBundleID(_ bundleID: String) -> Bool {
        let parts = bundleID.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-")
        return parts.allSatisfy { part in
            !part.isEmpty && part.unicodeScalars.allSatisfy { allowed.contains($0) }
        }
    }

    /// Words too generic to match system agents/helpers by name safely.
    private static let genericNameWords: Set<String> = [
        "app", "helper", "agent", "daemon", "update", "updater", "service",
        "installer", "uninstall", "launcher", "menu", "bar", "tool", "cli",
        "core", "main", "data", "cache", "support", "manager", "server", "client",
    ]

    /// A name distinctive enough to match system files by (≥5 chars, not generic).
    static func isSafeSystemName(_ name: String) -> Bool {
        let n = name.trimmingCharacters(in: .whitespaces)
        return n.count >= 5 && !genericNameWords.contains(n.lowercased())
    }

    /// Matches a filename to a bundle id only at a dot boundary, so "com.foo"
    /// matches "com.foo", "com.foo.plist", "com.foo.helper" — never "com.foobar".
    private static func startsWithBundleBoundary(_ filename: String, _ bundleID: String) -> Bool {
        filename == bundleID || filename.hasPrefix(bundleID + ".") || filename.hasPrefix(bundleID + " ")
    }

    private static func isAppleName(_ filename: String) -> Bool {
        filename.hasPrefix("com.apple.")
    }

    // MARK: Candidate catalogs

    /// Exact per-user paths worth probing (Trash-removable). Always confined to
    /// the home folder.
    static func userCandidates(bundleID: String?, appName: String, home: URL) -> [(URL, Leftover.Category)] {
        let library = home.appendingPathComponent("Library", isDirectory: true)
        var candidates: [(URL, Leftover.Category)] = []
        func add(_ relative: String, _ category: Leftover.Category, under base: URL) {
            guard !relative.isEmpty else { return }
            candidates.append((base.appendingPathComponent(relative), category))
        }

        for variant in nameVariants(appName) {
            add("Application Support/\(variant)", .appSupport, under: library)
            add("Caches/\(variant)", .caches, under: library)
            add("Logs/\(variant)", .logs, under: library)
            add("Preferences/\(variant)", .preferences, under: library)
            add("Preferences/\(variant).plist", .preferences, under: library)
            add("Saved Application State/\(variant).savedState", .savedState, under: library)
            // Plug-ins and extensions an app may install into the user Library.
            add("Services/\(variant).workflow", .plugins, under: library)
            add("QuickLook/\(variant).qlgenerator", .plugins, under: library)
            add("Spotlight/\(variant).mdimporter", .plugins, under: library)
            add("Internet Plug-Ins/\(variant).plugin", .plugins, under: library)
            add("PreferencePanes/\(variant).prefPane", .plugins, under: library)
            add("Screen Savers/\(variant).saver", .plugins, under: library)
            add("Input Methods/\(variant).app", .plugins, under: library)
            add("Frameworks/\(variant).framework", .plugins, under: library)
            add("ColorPickers/\(variant).colorPicker", .plugins, under: library)
            add("Contextual Menu Items/\(variant).plugin", .plugins, under: library)
            add("Address Book Plug-Ins/\(variant).bundle", .plugins, under: library)
            add("Mail/Bundles/\(variant).mailbundle", .plugins, under: library)
            add("Audio/Plug-Ins/Components/\(variant).component", .plugins, under: library)
            add("Audio/Plug-Ins/VST/\(variant).vst", .plugins, under: library)
            add("Audio/Plug-Ins/VST3/\(variant).vst3", .plugins, under: library)
            // Dotfile conventions.
            add(".config/\(variant)", .appSupport, under: home)
            add(".cache/\(variant)", .caches, under: home)
            add(".local/share/\(variant)", .appSupport, under: home)
            add(".\(variant)", .appSupport, under: home)
            add(".\(variant)rc", .preferences, under: home)
        }

        if let bundleID, isValidBundleID(bundleID) {
            add("Application Support/\(bundleID)", .appSupport, under: library)
            add("Caches/\(bundleID)", .caches, under: library)
            add("Logs/\(bundleID)", .logs, under: library)
            add("Preferences/\(bundleID).plist", .preferences, under: library)
            add("Saved Application State/\(bundleID).savedState", .savedState, under: library)
            add("Containers/\(bundleID)", .containers, under: library)
            add("WebKit/\(bundleID)", .webData, under: library)
            add("HTTPStorages/\(bundleID)", .webData, under: library)
            add("HTTPStorages/\(bundleID).binarycookies", .webData, under: library)
            add("Cookies/\(bundleID).binarycookies", .webData, under: library)
            add("Application Scripts/\(bundleID)", .scripts, under: library)
            add("Autosave Information/\(bundleID)", .savedState, under: library)
            add("SyncedPreferences/\(bundleID).plist", .preferences, under: library)
        }
        return candidates
    }

    /// Backward-compatible alias — the user catalog is what "candidate paths"
    /// has always meant.
    static func candidatePaths(bundleID: String?, appName: String, home: URL) -> [(URL, Leftover.Category)] {
        userCandidates(bundleID: bundleID, appName: appName, home: home)
    }

    /// Exact system-level paths worth probing (admin, permanent). Always
    /// confined to allowlisted `/Library` roots — never `/System`.
    static func systemCandidates(bundleID: String?, appName: String) -> [(URL, Leftover.Category)] {
        let lib = URL(fileURLWithPath: "/Library", isDirectory: true)
        var candidates: [(URL, Leftover.Category)] = []
        func add(_ relative: String, _ category: Leftover.Category) {
            candidates.append((lib.appendingPathComponent(relative), category))
        }

        if isSafeSystemName(appName) {
            for variant in nameVariants(appName) {
                add("Application Support/\(variant)", .appSupport)
                add("Caches/\(variant)", .caches)
                add("Logs/\(variant)", .logs)
                add("Preferences/\(variant)", .preferences)
                add("Preferences/\(variant).plist", .preferences)
                add("Frameworks/\(variant).framework", .plugins)
                add("Internet Plug-Ins/\(variant).plugin", .plugins)
                add("QuickLook/\(variant).qlgenerator", .plugins)
                add("PreferencePanes/\(variant).prefPane", .plugins)
                add("Screen Savers/\(variant).saver", .plugins)
                add("Input Methods/\(variant).app", .plugins)
                add("Audio/Plug-Ins/Components/\(variant).component", .plugins)
                add("Audio/Plug-Ins/VST/\(variant).vst", .plugins)
                add("Audio/Plug-Ins/VST3/\(variant).vst3", .plugins)
                add("Extensions/\(variant).kext", .plugins)
                add("StartupItems/\(variant)", .plugins)
            }
        }
        if let bundleID, isValidBundleID(bundleID) {
            add("Application Support/\(bundleID)", .appSupport)
            add("Caches/\(bundleID)", .caches)
            add("Logs/\(bundleID)", .logs)
            add("Preferences/\(bundleID).plist", .preferences)
            add("LaunchAgents/\(bundleID).plist", .launchAgents)
            add("LaunchDaemons/\(bundleID).plist", .launchAgents)
            add("Receipts/\(bundleID).bom", .receipts)
            add("Receipts/\(bundleID).plist", .receipts)
        }
        return candidates
    }

    // MARK: Scan

    private static func entries(of url: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [])) ?? []
    }

    /// Probes the filesystem and returns every leftover that actually exists,
    /// with sizes — both user-domain (Trash) and system-domain (admin).
    static func scan(bundleID: String?, appName: String, appURL: URL? = nil) -> [Leftover] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var found: [Leftover] = []
        var seen = Set<URL>()

        func consider(_ url: URL, _ category: Leftover.Category, _ domain: Leftover.Domain) {
            let standardized = url.standardizedFileURL
            // Universal guards — never touch the sealed system volume or Vitals.
            guard !standardized.path.hasPrefix("/System") else { return }
            guard fm.fileExists(atPath: standardized.path), seen.insert(standardized).inserted else { return }
            found.append(Leftover(id: standardized, category: category, domain: domain,
                                  sizeBytes: AppInventory.directorySize(standardized)))
        }

        for (url, category) in userCandidates(bundleID: bundleID, appName: appName, home: home) {
            consider(url, category, .user)
        }
        for (url, category) in systemCandidates(bundleID: bundleID, appName: appName) {
            consider(url, category, .system)
        }

        let validBundle = bundleID.flatMap { isValidBundleID($0) ? $0 : nil }

        // Dynamic user-domain finds that need directory enumeration.
        if let bundleID = validBundle {
            for url in entries(of: home.appendingPathComponent("Library/LaunchAgents"))
            where startsWithBundleBoundary(url.lastPathComponent, bundleID) {
                consider(url, .launchAgents, .user)
            }
            for url in entries(of: home.appendingPathComponent("Library/Group Containers"))
            where url.lastPathComponent.contains(bundleID) {
                consider(url, .containers, .user)
            }
            for url in entries(of: home.appendingPathComponent("Library/Preferences/ByHost"))
            where url.lastPathComponent.hasPrefix(bundleID + ".") && url.pathExtension == "plist" {
                consider(url, .preferences, .user)
            }
        }
        // Launch agents that point at the app bundle by path, even if named differently.
        if let appURL {
            for url in entries(of: home.appendingPathComponent("Library/LaunchAgents")) where url.pathExtension == "plist" {
                if let text = try? String(contentsOf: url, encoding: .utf8), text.contains(appURL.path) {
                    consider(url, .launchAgents, .user)
                }
            }
        }
        // The app's own crash logs (user + system).
        if isSafeSystemName(appName) {
            let appNameLower = appName.lowercased()
            for base in ["Library/Logs/DiagnosticReports"] {
                for url in entries(of: home.appendingPathComponent(base))
                where url.lastPathComponent.lowercased().hasPrefix(appNameLower) {
                    consider(url, .crashReports, .user)
                }
            }
            for url in entries(of: URL(fileURLWithPath: "/Library/Logs/DiagnosticReports"))
            where url.lastPathComponent.lowercased().hasPrefix(appNameLower) {
                consider(url, .crashReports, .system)
            }
        }

        // Dynamic system-domain finds.
        if let bundleID = validBundle {
            for base in ["/Library/LaunchAgents", "/Library/LaunchDaemons"] {
                for url in entries(of: URL(fileURLWithPath: base))
                where url.pathExtension == "plist"
                    && startsWithBundleBoundary(url.lastPathComponent, bundleID)
                    && !isAppleName(url.lastPathComponent) {
                    consider(url, .launchAgents, .system)
                }
            }
            for url in entries(of: URL(fileURLWithPath: "/Library/PrivilegedHelperTools"))
            where startsWithBundleBoundary(url.lastPathComponent, bundleID) && !isAppleName(url.lastPathComponent) {
                consider(url, .helperTools, .system)
            }
            for base in ["/private/var/db/receipts", "/Library/Receipts"] {
                for url in entries(of: URL(fileURLWithPath: base))
                where startsWithBundleBoundary(url.lastPathComponent, bundleID) && !isAppleName(url.lastPathComponent) {
                    consider(url, .receipts, .system)
                }
            }
        }
        // System launch agents/daemons by distinctive name (skip Apple's own).
        if isSafeSystemName(appName) {
            for base in ["/Library/LaunchAgents", "/Library/LaunchDaemons"] {
                for url in entries(of: URL(fileURLWithPath: base))
                where url.pathExtension == "plist"
                    && url.lastPathComponent.localizedCaseInsensitiveContains(appName)
                    && !isAppleName(url.lastPathComponent) {
                    consider(url, .launchAgents, .system)
                }
            }
        }

        return found.sorted {
            if $0.domain != $1.domain { return $0.domain == .user }  // user first
            return $0.sizeBytes > $1.sizeBytes
        }
    }

    // MARK: Homebrew

    private static func brewExecutable() -> String? {
        for path in ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
        where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }

    /// Tokens of every installed Homebrew cask. Empty if brew isn't present.
    /// Runs `brew` as the user — no admin.
    static func installedCaskTokens() -> [String] {
        guard let brew = brewExecutable() else { return [] }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: brew)
        process.arguments = ["list", "--cask", "-1"]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return [] }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return [] }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        return (String(data: data, encoding: .utf8) ?? "")
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// The Homebrew cask token for this app, if it looks installed via brew.
    /// Best-effort: matches the normalized app name against installed tokens.
    static func homebrewCask(appName: String, installedCasks: [String]) -> String? {
        guard !installedCasks.isEmpty else { return nil }
        let tokens = Set(installedCasks)
        let lower = appName.lowercased()
        for candidate in [lower.replacingOccurrences(of: " ", with: "-"),
                          lower.replacingOccurrences(of: " ", with: "")]
        where tokens.contains(candidate) {
            return candidate
        }
        return nil
    }

    // MARK: System extensions (detect + warn only)

    /// Orphaned system extensions that look like they belong to this app. These
    /// are OS-managed, so Vitals only surfaces them for manual removal — it
    /// never force-deletes them (matching Mole's behavior).
    static func systemExtensions(bundleID: String?) -> [URL] {
        guard let bundleID, isValidBundleID(bundleID) else { return [] }
        let base = URL(fileURLWithPath: "/Library/SystemExtensions")
        guard FileManager.default.fileExists(atPath: base.path),
              let enumerator = FileManager.default.enumerator(
                at: base, includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles], errorHandler: { _, _ in true }) else { return [] }

        var found: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "systemextension" {
            let name = url.deletingPathExtension().lastPathComponent
            if startsWithBundleBoundary(name, bundleID) { found.append(url) }
        }
        return found
    }
}
