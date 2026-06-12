import Foundation

/// A category of reclaimable disk space, with the concrete items that would
/// be removed. Every category is regenerable data (caches, logs, trash) —
/// never documents, projects, or settings.
struct CleanupCategory: Identifiable {
    enum Kind: String, CaseIterable, Identifiable {
        case xcode
        case devCaches
        case homebrew
        case appCaches
        case logs
        case trash

        var id: String { rawValue }

        var title: String {
            switch self {
            case .xcode: return "Xcode derived data"
            case .devCaches: return "Developer caches"
            case .homebrew: return "Homebrew cache"
            case .appCaches: return "App caches"
            case .logs: return "Logs"
            case .trash: return "Trash"
            }
        }

        var detail: String {
            switch self {
            case .xcode: return "Build products Xcode recreates on the next build"
            case .devCaches: return "npm, bun, yarn, pip, cargo, Gradle, CocoaPods, Go package caches"
            case .homebrew: return "Downloaded bottles and old formula versions"
            case .appCaches: return "Per-app caches in ~/Library/Caches (Apple system caches are kept)"
            case .logs: return "App logs in ~/Library/Logs (crash reports are kept)"
            case .trash: return "Files already in the Trash, removed permanently"
            }
        }

        var symbol: String {
            switch self {
            case .xcode: return "hammer"
            case .devCaches: return "shippingbox"
            case .homebrew: return "mug"
            case .appCaches: return "internaldrive"
            case .logs: return "doc.text"
            case .trash: return "trash"
            }
        }
    }

    let kind: Kind
    var items: [URL]
    var sizeBytes: UInt64

    var id: Kind { kind }
}

/// Scans and clears well-understood, regenerable data. Cleaning deletes
/// directly (moving caches to the Trash would free nothing); the categories
/// are chosen so deletion is always safe.
enum DiskCleaner {
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

    /// Logs entries that are kept: diagnostic/crash reports are small and
    /// can matter for debugging hardware problems — Vitals' own audience.
    static func shouldOfferLog(named name: String) -> Bool {
        name != "DiagnosticReports" && name != "CrashReporter"
    }

    static func scan() -> [CleanupCategory] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let library = home.appendingPathComponent("Library", isDirectory: true)

        func existing(_ urls: [URL]) -> [URL] {
            urls.filter { fm.fileExists(atPath: $0.path) }
        }

        func children(of url: URL, where include: (String) -> Bool = { _ in true }) -> [URL] {
            ((try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [])) ?? [])
                .filter { include($0.lastPathComponent) }
        }

        var categories: [CleanupCategory] = []

        categories.append(.init(kind: .xcode, items: existing([
            library.appendingPathComponent("Developer/Xcode/DerivedData"),
        ]), sizeBytes: 0))

        categories.append(.init(kind: .devCaches, items: existing([
            home.appendingPathComponent(".npm/_cacache"),
            home.appendingPathComponent(".bun/install/cache"),
            library.appendingPathComponent("Caches/Yarn"),
            library.appendingPathComponent("Caches/pip"),
            library.appendingPathComponent("Caches/CocoaPods"),
            library.appendingPathComponent("Caches/go-build"),
            home.appendingPathComponent(".cargo/registry/cache"),
            home.appendingPathComponent(".gradle/caches"),
        ]), sizeBytes: 0))

        categories.append(.init(kind: .homebrew, items: existing([
            library.appendingPathComponent("Caches/Homebrew"),
        ]), sizeBytes: 0))

        categories.append(.init(
            kind: .appCaches,
            items: children(of: library.appendingPathComponent("Caches"), where: shouldOfferCache),
            sizeBytes: 0
        ))

        categories.append(.init(
            kind: .logs,
            items: children(of: library.appendingPathComponent("Logs"), where: shouldOfferLog),
            sizeBytes: 0
        ))

        categories.append(.init(
            kind: .trash,
            items: children(of: home.appendingPathComponent(".Trash")),
            sizeBytes: 0
        ))

        return categories
    }

    static func size(of category: CleanupCategory) -> UInt64 {
        category.items.reduce(0) { $0 + AppInventory.directorySize($1) }
    }

    struct CleanResult {
        var freedBytes: UInt64 = 0
        var removedItems = 0
        var failures: [(url: URL, reason: String)] = []
    }

    /// Removes the contents of the given categories. Items are deleted, not
    /// trashed — these are caches and logs whose entire point is that the
    /// system can regenerate them.
    static func clean(_ categories: [CleanupCategory]) -> CleanResult {
        let fm = FileManager.default
        var result = CleanResult()
        for category in categories {
            for url in category.items {
                let size = AppInventory.directorySize(url)
                do {
                    try fm.removeItem(at: url)
                    result.freedBytes += size
                    result.removedItems += 1
                } catch {
                    result.failures.append((url, error.localizedDescription))
                }
            }
        }
        return result
    }
}
