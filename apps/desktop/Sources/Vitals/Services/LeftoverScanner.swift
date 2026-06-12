import Foundation

/// A file or folder an app left behind outside its bundle.
struct Leftover: Identifiable, Hashable {
    enum Category: String, CaseIterable {
        case appSupport = "Application Support"
        case caches = "Caches"
        case preferences = "Preferences"
        case logs = "Logs"
        case savedState = "Saved State"
        case containers = "Containers"
        case webData = "Web & Cookies"
        case launchAgents = "Launch Agents"
        case scripts = "Application Scripts"
    }

    let id: URL
    let category: Category
    var sizeBytes: UInt64
}

/// Locates the per-user files an app leaves behind, by probing the standard
/// macOS locations under ~/Library (plus dotfile conventions) for the app's
/// bundle identifier and name variants. The set of locations follows
/// long-established uninstaller practice (see e.g. the Mole project for a
/// battle-tested catalog of where apps hide data).
///
/// Deliberately user-domain only: nothing under /Library or /System is ever
/// returned, so nothing this scanner finds needs elevated rights to remove.
enum LeftoverScanner {
    /// Apps name their folders inconsistently ("My App", "MyApp", "my-app"),
    /// so probe every common variant. Names shorter than 2 characters are
    /// rejected outright — they'd match far too broadly.
    static func nameVariants(_ name: String) -> [String] {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return [] }
        var variants = [
            trimmed,
            trimmed.replacingOccurrences(of: " ", with: ""),
            trimmed.replacingOccurrences(of: " ", with: "-"),
            trimmed.replacingOccurrences(of: " ", with: "_"),
        ]
        variants += variants.map { $0.lowercased() }
        var unique: [String] = []
        for variant in variants where !unique.contains(variant) && variant.count >= 2 {
            unique.append(variant)
        }
        return unique
    }

    /// Only reverse-DNS-looking identifiers may be used to build paths — a
    /// malformed Info.plist must not be able to inject globs or traversal.
    static func isValidBundleID(_ bundleID: String) -> Bool {
        let parts = bundleID.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-")
        return parts.allSatisfy { part in
            !part.isEmpty && part.unicodeScalars.allSatisfy { allowed.contains($0) }
        }
    }

    /// Exact paths worth probing for this app, before checking existence.
    static func candidatePaths(bundleID: String?, appName: String, home: URL) -> [(URL, Leftover.Category)] {
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
            add("Preferences/\(variant).plist", .preferences, under: library)
            add("Saved Application State/\(variant).savedState", .savedState, under: library)
            add(".config/\(variant)", .appSupport, under: home)
            add(".cache/\(variant)", .caches, under: home)
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

    /// Probes the filesystem and returns what actually exists, with sizes.
    static func scan(bundleID: String?, appName: String) -> [Leftover] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var found: [Leftover] = []
        var seen = Set<URL>()

        for (url, category) in candidatePaths(bundleID: bundleID, appName: appName, home: home) {
            guard fm.fileExists(atPath: url.path), seen.insert(url).inserted else { continue }
            found.append(Leftover(id: url, category: category, sizeBytes: AppInventory.directorySize(url)))
        }

        // Launch agents and group containers carry prefixes/suffixes around
        // the bundle id, so they need directory enumeration, not exact paths.
        if let bundleID, isValidBundleID(bundleID) {
            let agents = home.appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            if let entries = try? fm.contentsOfDirectory(at: agents, includingPropertiesForKeys: nil) {
                for url in entries where url.lastPathComponent.hasPrefix(bundleID) && seen.insert(url).inserted {
                    found.append(Leftover(id: url, category: .launchAgents, sizeBytes: AppInventory.directorySize(url)))
                }
            }
            let groups = home.appendingPathComponent("Library/Group Containers", isDirectory: true)
            if let entries = try? fm.contentsOfDirectory(at: groups, includingPropertiesForKeys: nil) {
                for url in entries where url.lastPathComponent.contains(bundleID) && seen.insert(url).inserted {
                    found.append(Leftover(id: url, category: .containers, sizeBytes: AppInventory.directorySize(url)))
                }
            }
        }

        return found.sorted { $0.sizeBytes > $1.sizeBytes }
    }
}
