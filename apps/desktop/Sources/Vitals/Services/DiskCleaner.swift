import Foundation

/// How far a cleanup reaches.
enum CleanDepth: String, CaseIterable, Identifiable {
    /// User-domain caches, logs, and Trash — no admin, today's behavior.
    case quick
    /// Adds system-level junk that needs administrator rights.
    case deep

    var id: String { rawValue }
    var title: String { self == .quick ? "Quick" : "Deep" }
}

/// A category of reclaimable disk space, with the concrete items that would
/// be removed. Every category is regenerable data (caches, logs, trash) —
/// never documents, projects, or settings. System categories are age-gated:
/// only files older than a retention window are touched.
struct CleanupCategory: Identifiable {
    enum Kind: String, CaseIterable, Identifiable {
        // Quick (user domain, no admin)
        case xcode
        case devCaches
        case deviceSupport
        case browserCaches
        case deviceFirmware
        case homebrew
        case appCaches
        case logs
        case trash
        // Deep, user domain (no admin)
        case recentItems
        case deviceBackups
        // Deep, system (admin, age-gated)
        case systemCaches
        case systemLogs
        case crashReports
        case systemTemp
        case gpuCaches

        var id: String { rawValue }

        /// System categories need root to delete; the rest run in-process.
        var requiresAdmin: Bool {
            switch self {
            case .systemCaches, .systemLogs, .crashReports, .systemTemp, .gpuCaches: return true
            default: return false
            }
        }

        /// Irreversible removal of data that isn't merely regenerable cache —
        /// an iOS device backup may be the only copy of a phone. These are never
        /// auto-anything: off by default and gated behind a second, explicit
        /// confirmation that names exactly what will be destroyed.
        var isDestructive: Bool {
            switch self {
            case .deviceBackups: return true
            default: return false
            }
        }

        /// The shallowest depth at which this category is offered.
        var minimumDepth: CleanDepth {
            switch self {
            case .xcode, .devCaches, .deviceSupport, .browserCaches, .deviceFirmware,
                 .homebrew, .appCaches, .logs, .trash: return .quick
            default: return .deep
            }
        }

        var title: String {
            switch self {
            case .xcode: return "Xcode derived data"
            case .devCaches: return "Developer caches"
            case .deviceSupport: return "Device support files"
            case .browserCaches: return "Browser caches"
            case .deviceFirmware: return "Device firmware"
            case .deviceBackups: return "iOS device backups"
            case .homebrew: return "Homebrew cache"
            case .appCaches: return "App caches"
            case .logs: return "Logs"
            case .trash: return "Trash"
            case .recentItems: return "Recent items"
            case .systemCaches: return "System caches"
            case .systemLogs: return "System logs"
            case .crashReports: return "Crash reports"
            case .systemTemp: return "System temp files"
            case .gpuCaches: return "GPU shader caches"
            }
        }

        var detail: String {
            switch self {
            case .xcode: return "Build products Xcode recreates on the next build"
            case .devCaches: return "npm, yarn, pnpm, bun, pip, Poetry, cargo, Go, Gradle, Maven, CocoaPods, SwiftPM, Docker, Playwright, JetBrains and more"
            case .deviceSupport: return "Xcode device-support symbols and simulator caches, re-downloaded on demand"
            case .browserCaches: return "Chrome, Brave, Edge, Arc, Firefox and other browser caches (history, cookies and logins are kept)"
            case .deviceFirmware: return "Cached iPhone/iPad/iPod firmware (.ipsw) older than 14 days, re-downloadable"
            case .deviceBackups: return "Permanently deletes local iPhone/iPad backups — make sure you have another copy"
            case .homebrew: return "Downloaded bottles and old formula versions"
            case .appCaches: return "Per-app caches in ~/Library/Caches (Apple system caches are kept)"
            case .logs: return "App logs in ~/Library/Logs"
            case .trash: return "Files already in the Trash, removed permanently"
            case .recentItems: return "Recently-opened file and server lists (the files stay)"
            case .systemCaches: return "Old .cache/.tmp/.log files in /Library/Caches (7+ days)"
            case .systemLogs: return "Old system logs in /private/var/log (7+ days)"
            case .crashReports: return "Crash and diagnostic reports older than 7 days"
            case .systemTemp: return "Stale files in /private/tmp and /var/tmp (3+ days)"
            case .gpuCaches: return "Stale Metal/GPU shader caches the system rebuilds"
            }
        }

        var symbol: String {
            switch self {
            case .xcode: return "hammer"
            case .devCaches: return "shippingbox"
            case .deviceSupport: return "iphone.gen3"
            case .browserCaches: return "safari"
            case .deviceFirmware: return "cpu"
            case .deviceBackups: return "externaldrive.badge.icloud"
            case .homebrew: return "mug"
            case .appCaches: return "internaldrive"
            case .logs: return "doc.text"
            case .trash: return "trash"
            case .recentItems: return "clock.arrow.circlepath"
            case .systemCaches: return "gearshape"
            case .systemLogs: return "doc.badge.gearshape"
            case .crashReports: return "exclamationmark.triangle"
            case .systemTemp: return "clock.badge.xmark"
            case .gpuCaches: return "cpu"
            }
        }
    }

    let kind: Kind
    var items: [URL]
    var sizeBytes: UInt64

    var id: Kind { kind }
}

/// Scans and clears well-understood, regenerable data. User-domain cleaning
/// deletes directly (moving caches to the Trash would free nothing); system
/// cleaning runs a vetted, age-gated script as root through `PrivilegedShell`.
enum DiskCleaner {
    // MARK: Retention windows (mirrors Mole's MOLE_*_AGE_DAYS)

    static let systemCacheAgeDays = 7
    static let logAgeDays = 7
    static let crashReportAgeDays = 7
    static let tempAgeDays = 3
    static let gpuCacheAgeDays = 1
    /// Cached device firmware is kept this long before it's offered (Mole's gate).
    static let firmwareAgeDays = 14

    // MARK: Quick-mode protection rules (kept strict)

    /// ~/Library/Caches entries that are never offered for cleaning: Apple's
    /// system caches and anything covered by its own category.
    static let protectedCacheNames: [String] = [
        "Homebrew",  // its own category
    ]
    static let protectedCachePrefixes: [String] = [
        "com.apple.",
        "CloudKit",
        "FamilyCircle",
    ]

    static func shouldOfferCache(named name: String) -> Bool {
        if protectedCacheNames.contains(name) { return false }
        return !protectedCachePrefixes.contains { name.hasPrefix($0) }
    }

    /// Logs entries kept out of the user-domain Logs category: diagnostic and
    /// crash reports. (Deep mode offers them separately, age-gated, as their
    /// own admin category.)
    static func shouldOfferLog(named name: String) -> Bool {
        name != "DiagnosticReports" && name != "CrashReporter"
    }

    // MARK: Scanning

    static func scan(depth: CleanDepth) -> [CleanupCategory] {
        var categories = quickCategories()
        if depth == .deep {
            categories.append(contentsOf: deepUserCategories())
            categories.append(contentsOf: deepSystemCategories())
        }
        return categories
    }

    private static func quickCategories() -> [CleanupCategory] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let library = home.appendingPathComponent("Library", isDirectory: true)

        func existing(_ urls: [URL]) -> [URL] { urls.filter { fm.fileExists(atPath: $0.path) } }
        func children(of url: URL, where include: (String) -> Bool = { _ in true }) -> [URL] {
            ((try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [])) ?? [])
                .filter { include($0.lastPathComponent) }
        }

        return [
            .init(kind: .xcode, items: existing([
                library.appendingPathComponent("Developer/Xcode/DerivedData"),
            ]), sizeBytes: 0),
            .init(kind: .devCaches, items: existing([
                // JavaScript / Node
                home.appendingPathComponent(".npm/_cacache"),
                home.appendingPathComponent(".bun/install/cache"),
                library.appendingPathComponent("Caches/Yarn"),
                home.appendingPathComponent(".cache/yarn"),
                home.appendingPathComponent(".yarn/berry/cache"),
                home.appendingPathComponent(".pnpm-store"),
                home.appendingPathComponent(".cache/node/corepack"),
                home.appendingPathComponent(".deno"),
                home.appendingPathComponent(".cache/electron"),
                home.appendingPathComponent(".cache/electron-builder"),
                home.appendingPathComponent(".cache/node-gyp"),
                library.appendingPathComponent("Caches/node-gyp"),
                library.appendingPathComponent("Caches/ms-playwright"),
                home.appendingPathComponent(".cache/ms-playwright"),
                // Python
                library.appendingPathComponent("Caches/pip"),
                home.appendingPathComponent(".cache/pip"),
                home.appendingPathComponent(".cache/uv"),
                home.appendingPathComponent(".cache/pypoetry"),
                home.appendingPathComponent(".cache/pre-commit"),
                // Rust / Go
                home.appendingPathComponent(".cargo/registry/cache"),
                library.appendingPathComponent("Caches/go-build"),
                home.appendingPathComponent("go/pkg/mod/cache/download"),
                // JVM
                home.appendingPathComponent(".gradle/caches"),
                home.appendingPathComponent(".m2/repository"),
                home.appendingPathComponent(".ivy2/cache"),
                home.appendingPathComponent(".sbt/boot"),
                // Apple / mobile
                library.appendingPathComponent("Caches/CocoaPods"),
                library.appendingPathComponent("Caches/org.swift.swiftpm"),
                home.appendingPathComponent(".pub-cache"),
                home.appendingPathComponent(".android/cache"),
                home.appendingPathComponent(".android/build-cache"),
                // Ruby / containers / IDEs
                home.appendingPathComponent(".bundle/cache"),
                home.appendingPathComponent(".docker/buildx"),
                library.appendingPathComponent("Caches/JetBrains"),
            ]), sizeBytes: 0),
            .init(kind: .deviceSupport, items: existing([
                library.appendingPathComponent("Developer/Xcode/iOS DeviceSupport"),
                library.appendingPathComponent("Developer/Xcode/watchOS DeviceSupport"),
                library.appendingPathComponent("Developer/Xcode/tvOS DeviceSupport"),
                library.appendingPathComponent("Developer/Xcode/macOS DeviceSupport"),
                library.appendingPathComponent("Developer/Xcode/xrOS DeviceSupport"),
                library.appendingPathComponent("Developer/CoreSimulator/Caches"),
            ]), sizeBytes: 0),
            .init(kind: .browserCaches, items: browserCacheDirs(home: home), sizeBytes: 0),
            .init(kind: .deviceFirmware, items: iosFirmwareFiles(home: home), sizeBytes: 0),
            .init(kind: .homebrew, items: existing([
                library.appendingPathComponent("Caches/Homebrew"),
            ]), sizeBytes: 0),
            .init(kind: .appCaches,
                  items: children(of: library.appendingPathComponent("Caches"), where: shouldOfferCache),
                  sizeBytes: 0),
            .init(kind: .logs,
                  items: children(of: library.appendingPathComponent("Logs"), where: shouldOfferLog),
                  sizeBytes: 0),
            .init(kind: .trash,
                  items: children(of: home.appendingPathComponent(".Trash")),
                  sizeBytes: 0),
        ]
    }

    private static func deepUserCategories() -> [CleanupCategory] {
        let fm = FileManager.default
        let shared = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.sharedfilelist")
        let recentLists = ["RecentApplications", "RecentDocuments", "RecentServers", "RecentHosts"]
            .flatMap { ["com.apple.LSSharedFileList.\($0).sfl2", "com.apple.LSSharedFileList.\($0).sfl"] }
            .map { shared.appendingPathComponent($0) }
            .filter { fm.fileExists(atPath: $0.path) }

        // iOS device backups — reported like Mole, but offered for opt-in
        // removal too (off by default, second confirmation). Each backup folder
        // under MobileSync/Backup is a separate item so a stale one can go
        // without taking a current one.
        let backupRoot = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MobileSync/Backup")
        let backups = ((try? fm.contentsOfDirectory(at: backupRoot, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? [])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }

        return [
            .init(kind: .recentItems, items: recentLists, sizeBytes: 0),
            .init(kind: .deviceBackups, items: backups, sizeBytes: 0),
        ]
    }

    /// Cached iOS/iPadOS/iPod firmware images (`.ipsw`) older than the firmware
    /// retention window. Re-downloadable, so safe to clear (Mole clears these
    /// too). Fixed iTunes "Software Updates" roots only.
    static func iosFirmwareFiles(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        let roots = ["iPhone Software Updates", "iPad Software Updates", "iPod Software Updates"]
            .map { home.appendingPathComponent("Library/iTunes/\($0)") }
        return eligibleFiles(roots, extensions: ["ipsw"], olderThan: firmwareAgeDays, recursive: false)
            .map(\.url)
    }

    /// The number of Time Machine local snapshots on the boot volume. macOS
    /// manages these automatically (purging them under disk pressure); Mole and
    /// Vitals only report the count — there's no honest byte figure to show.
    /// Returns nil if Time Machine isn't configured or `tmutil` is unavailable.
    static func localSnapshotCount() -> Int? {
        let tmutil = "/usr/bin/tmutil"
        guard FileManager.default.isExecutableFile(atPath: tmutil) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tmutil)
        process.arguments = ["listlocalsnapshots", "/"]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let text = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let count = text.split(separator: "\n").filter { $0.contains("com.apple.TimeMachine.") }.count
        return count > 0 ? count : nil
    }

    private static func deepSystemCategories() -> [CleanupCategory] {
        // Items filled in lazily by `measured(_:)` — the age-eligible walk is
        // the expensive part and runs during the streamed sizing phase.
        [CleanupCategory.Kind.systemCaches, .systemLogs, .crashReports, .systemTemp, .gpuCaches]
            .map { CleanupCategory(kind: $0, items: [], sizeBytes: 0) }
    }

    // MARK: Measuring

    /// Returns the category with `items` and `sizeBytes` filled. User
    /// categories sum their listed items; system categories walk their fixed
    /// roots for the age-eligible files that the clean script would remove.
    static func measured(_ category: CleanupCategory) -> CleanupCategory {
        var category = category
        if category.kind.requiresAdmin {
            let eligible = systemEligibleFiles(for: category.kind)
            category.items = eligible.map(\.url)
            category.sizeBytes = eligible.reduce(0) { $0 + $1.size }
        } else {
            category.sizeBytes = category.items.reduce(0) { $0 + AppInventory.directorySize($1) }
        }
        return category
    }

    private struct EligibleFile { let url: URL; let size: UInt64 }

    private static func systemEligibleFiles(for kind: CleanupCategory.Kind) -> [EligibleFile] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch kind {
        case .systemCaches:
            return eligibleFiles([URL(fileURLWithPath: "/Library/Caches")],
                                 extensions: ["cache", "tmp", "log"], olderThan: systemCacheAgeDays, recursive: true)
        case .systemLogs:
            return eligibleFiles([URL(fileURLWithPath: "/private/var/log")],
                                 extensions: ["log", "gz", "asl"], olderThan: logAgeDays, recursive: true)
        case .crashReports:
            return eligibleFiles([
                URL(fileURLWithPath: "/Library/Logs/DiagnosticReports"),
                home.appendingPathComponent("Library/Logs/DiagnosticReports"),
            ], extensions: nil, olderThan: crashReportAgeDays, recursive: true)
        case .systemTemp:
            return eligibleFiles([URL(fileURLWithPath: "/private/tmp"), URL(fileURLWithPath: "/private/var/tmp")],
                                 extensions: nil, olderThan: tempAgeDays, recursive: false)
        case .gpuCaches:
            return eligibleFiles(gpuCacheDirs(), extensions: nil, olderThan: gpuCacheAgeDays, recursive: true)
        default:
            return []
        }
    }

    private static func eligibleFiles(_ roots: [URL], extensions: Set<String>?, olderThan days: Int, recursive: Bool) -> [EligibleFile] {
        let fm = FileManager.default
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .totalFileAllocatedSizeKey, .isRegularFileKey]
        var result: [EligibleFile] = []
        for root in roots {
            guard fm.fileExists(atPath: root.path) else { continue }
            let urls: [URL]
            if recursive {
                guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: Array(keys),
                                                     options: [], errorHandler: { _, _ in true }) else { continue }
                urls = enumerator.compactMap { $0 as? URL }
            } else {
                urls = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: Array(keys), options: [])) ?? []
            }
            for url in urls {
                if Task.isCancelled { return result }
                guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
                if let extensions, !extensions.contains(url.pathExtension.lowercased()) { continue }
                guard let modified = values.contentModificationDate, modified < cutoff else { continue }
                result.append(.init(url: url, size: UInt64(values.totalFileAllocatedSize ?? 0)))
            }
        }
        return result
    }

    /// Known per-user Metal/GPU shader cache directories under /var/folders.
    /// Fixed shape `…/C/<id>/com.apple.{metal,metalfe,gpuarchiver}` — never a
    /// broader match.
    private static func gpuCacheDirs() -> [URL] {
        let fm = FileManager.default
        let names = ["com.apple.metal", "com.apple.metalfe", "com.apple.gpuarchiver"]
        var dirs: [URL] = []
        let base = URL(fileURLWithPath: "/private/var/folders")
        guard let level1 = try? fm.contentsOfDirectory(at: base, includingPropertiesForKeys: nil) else { return [] }
        for a in level1 {
            guard let level2 = try? fm.contentsOfDirectory(at: a, includingPropertiesForKeys: nil) else { continue }
            for b in level2 {
                let cDir = b.appendingPathComponent("C")
                guard let level3 = try? fm.contentsOfDirectory(at: cDir, includingPropertiesForKeys: nil) else { continue }
                for d in level3 {
                    for name in names {
                        let dir = d.appendingPathComponent(name)
                        if fm.fileExists(atPath: dir.path) { dirs.append(dir) }
                    }
                }
            }
        }
        return dirs
    }

    /// Browser cache directories across the Chromium family and Firefox. Only
    /// ever returns *cache* subfolders — `Cache`, `Code Cache`, GPU/shader
    /// caches, and the Service Worker cache stores — built from a fixed list, so
    /// it can never reach a profile's `Cookies`, `History`, `Bookmarks` or
    /// `Login Data` (those live as siblings and are deliberately left alone).
    /// All regenerable: the browser refills them on next use.
    static func browserCacheDirs(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        let fm = FileManager.default
        let appSupport = home.appendingPathComponent("Library/Application Support")
        let caches = home.appendingPathComponent("Library/Caches")

        // Chromium-family install roots (each contains profile folders).
        let chromiumRoots = [
            "Google/Chrome", "Google/Chrome Beta", "Google/Chrome Canary",
            "BraveSoftware/Brave-Browser", "Microsoft Edge", "Chromium",
            "Vivaldi", "com.operasoftware.Opera", "Arc/User Data",
        ].map { appSupport.appendingPathComponent($0) }

        // Per-profile subfolders that hold only regenerable cache data.
        let profileCacheSubdirs = [
            "Cache", "Code Cache", "GPUCache", "DawnCache", "DawnGraphiteCache",
            "GrShaderCache", "ShaderCache",
            "Service Worker/CacheStorage", "Service Worker/ScriptCache",
        ]

        func directorySubentries(of url: URL) -> [URL] {
            guard fm.fileExists(atPath: url.path) else { return [] }
            return ((try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [])) ?? [])
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        }

        var dirs: [URL] = []
        for root in chromiumRoots {
            // The root itself and each profile under it can hold a cache.
            for profile in [root] + directorySubentries(of: root) {
                for sub in profileCacheSubdirs {
                    let dir = profile.appendingPathComponent(sub)
                    if fm.fileExists(atPath: dir.path) { dirs.append(dir) }
                }
            }
        }
        // Firefox keeps its cache under ~/Library/Caches, not Application Support.
        let firefox = caches.appendingPathComponent("Firefox")
        if fm.fileExists(atPath: firefox.path) { dirs.append(firefox) }
        return dirs
    }

    // MARK: Cleaning

    struct CleanResult {
        /// A user-domain item the in-process pass couldn't delete (root-owned
        /// cache file, permission-locked Trash entry). Carries its measured size
        /// so a privileged retry can credit it once the file is actually gone.
        struct Failure { let url: URL; let size: UInt64; let reason: String }

        var freedBytes: UInt64 = 0
        var removedItems = 0
        var failures: [Failure] = []
        var usedAdmin = false
    }

    /// Removes the contents of user-domain categories in-process. Items are
    /// deleted, not trashed — these are caches and logs the system regenerates.
    /// System categories are NOT handled here; they go through `systemCleanScript`.
    static func clean(_ categories: [CleanupCategory]) -> CleanResult {
        let fm = FileManager.default
        var result = CleanResult()
        for category in categories where !category.kind.requiresAdmin {
            for url in category.items {
                let size = AppInventory.directorySize(url)
                do {
                    try fm.removeItem(at: url)
                    result.freedBytes += size
                    result.removedItems += 1
                } catch {
                    Log.notice(.cleanup, "couldn't remove \(url.lastPathComponent)", error: error)
                    result.failures.append(.init(url: url, size: size, reason: error.localizedDescription))
                }
            }
        }
        return result
    }

    /// A root `rm -rf` script for user-domain cleanup items the in-process pass
    /// couldn't delete — root-owned cache files, permission-locked Trash entries.
    /// This is the cleanup counterpart to the uninstaller's blocked-bundle
    /// fallback: every path is re-validated against the fixed set of user
    /// cleanup roots, independently of how it was discovered — absolute, inside
    /// the home folder, no `..`, never the bare home, never `/System`. Anything
    /// that fails validation is dropped, never executed. Returns nil if nothing
    /// survives.
    static func userCleanFallbackScript(
        for paths: [URL],
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> String? {
        let homePath = home.standardizedFileURL.path
        // Roots mirror the user-domain categories in `quickCategories` /
        // `deepUserCategories`. Matched as a whole path or a path prefix so
        // `.npm` never matches `.npmrc`.
        let allowedRoots = [
            "Library/Caches",
            "Library/Logs",
            "Library/Developer",
            "Library/Application Support/com.apple.sharedfilelist",
            ".Trash",
            ".npm", ".bun", ".cargo", ".gradle", ".cache", ".pnpm-store", ".deno",
        ].map { homePath + "/" + $0 }

        var lines = ["#!/bin/sh", "# Vitals cleanup retry — validated user-domain paths only."]
        var any = false
        for url in paths {
            let path = url.standardizedFileURL.path
            guard path.hasPrefix("/"), path != "/", path != homePath,
                  !path.contains(".."), !path.contains("'") else { continue }
            guard !path.hasPrefix("/System") else { continue }
            guard allowedRoots.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) else { continue }
            lines.append("rm -rf '\(path)' 2>/dev/null || true")
            any = true
        }
        return any ? lines.joined(separator: "\n") : nil
    }

    /// A root shell script that deletes only age-gated files under a fixed set
    /// of allowlisted system roots. Built entirely from constants — never from
    /// UI-supplied paths — so the privileged side is auditable and bounded.
    /// Never references /System, never a bare path, always `-mtime` gated.
    static func systemCleanScript(for kinds: Set<CleanupCategory.Kind>) -> String {
        var lines = ["#!/bin/sh", "# Vitals deep clean — age-gated, fixed roots only."]

        func findDelete(_ root: String, extensions: [String], age: Int, recursive: Bool) {
            let depth = recursive ? "" : "-maxdepth 1 "
            if extensions.isEmpty {
                lines.append("find '\(root)' \(depth)-type f -mtime +\(age) -delete 2>/dev/null || true")
            } else {
                let nameExpr = extensions.map { "-name '*.\($0)'" }.joined(separator: " -o ")
                lines.append("find '\(root)' \(depth)-type f \\( \(nameExpr) \\) -mtime +\(age) -delete 2>/dev/null || true")
            }
        }

        let userDiagnostics = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/DiagnosticReports").path

        for kind in kinds.sorted(by: { $0.rawValue < $1.rawValue }) where kind.requiresAdmin {
            switch kind {
            case .systemCaches:
                findDelete("/Library/Caches", extensions: ["cache", "tmp", "log"], age: systemCacheAgeDays, recursive: true)
            case .systemLogs:
                findDelete("/private/var/log", extensions: ["log", "gz", "asl"], age: logAgeDays, recursive: true)
            case .crashReports:
                findDelete("/Library/Logs/DiagnosticReports", extensions: [], age: crashReportAgeDays, recursive: true)
                findDelete(userDiagnostics, extensions: [], age: crashReportAgeDays, recursive: true)
            case .systemTemp:
                findDelete("/private/tmp", extensions: [], age: tempAgeDays, recursive: false)
                findDelete("/private/var/tmp", extensions: [], age: tempAgeDays, recursive: false)
            case .gpuCaches:
                for dir in gpuCacheDirs() {
                    findDelete(dir.path, extensions: [], age: gpuCacheAgeDays, recursive: true)
                }
            default:
                break
            }
        }
        return lines.joined(separator: "\n")
    }
}
