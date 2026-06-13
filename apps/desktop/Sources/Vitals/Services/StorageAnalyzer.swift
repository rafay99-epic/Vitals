import Foundation

/// One entry in the storage analyzer: a file or folder directly inside the
/// path being analyzed, with its on-disk size. Sizes are measured the honest
/// way — actual allocated bytes (`AppInventory.directorySize`), so sparse and
/// cloud-placeholder files count what they really occupy.
struct StorageEntry: Identifiable, Hashable {
    let url: URL
    let name: String
    var sizeBytes: UInt64
    let isDirectory: Bool

    var id: URL { url }
}

/// A top-level location in the occupied-storage overview. The four are chosen
/// to be **non-overlapping** so their sizes add up without double counting —
/// User Files is the home folder *excluding* ~/Library, which is its own
/// category (the same separation Mole's analyzer makes). Each category is also
/// an entry point: opening one drills the analyzer into `root`.
struct StorageCategory: Identifiable {
    enum Kind: String, CaseIterable, Identifiable {
        case userFiles
        case userLibrary
        case applications
        case systemLibrary

        var id: String { rawValue }

        var title: String {
            switch self {
            case .userFiles: return "User Files"
            case .userLibrary: return "User Library"
            case .applications: return "Applications"
            case .systemLibrary: return "System Library"
            }
        }

        var detail: String {
            switch self {
            case .userFiles: return "Everything in your home folder except Library"
            case .userLibrary: return "~/Library — app support, caches, containers"
            case .applications: return "Apps installed in /Applications"
            case .systemLibrary: return "/Library — shared system support files"
            }
        }

        var symbol: String {
            switch self {
            case .userFiles: return "house"
            case .userLibrary: return "person.crop.square"
            case .applications: return "square.grid.2x2"
            case .systemLibrary: return "gearshape"
            }
        }
    }

    let kind: Kind
    /// Where opening this category sends the analyzer.
    let root: URL
    /// Directories summed to produce the category size. Equal to `[root]`
    /// except for User Files, which sums every home child but Library.
    let scanRoots: [URL]
    var sizeBytes: UInt64

    var id: Kind { kind }
}

/// Reads disk capacity and measures where occupied space lives. UI-free, like
/// every other Service: it talks to the filesystem and knows nothing about the
/// views that display it. Reading is liberal here — nothing in this type ever
/// writes, deletes, or moves a file.
enum StorageAnalyzer {
    /// Capacity of a mounted volume. `free` uses the "important usage"
    /// figure — the same number Finder shows as Available, which accounts for
    /// purgeable space the system would reclaim under pressure.
    struct VolumeUsage: Equatable {
        let total: UInt64
        let free: UInt64

        var used: UInt64 { total > free ? total - free : 0 }
        var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
    }

    static func volumeUsage(for url: URL = URL(fileURLWithPath: "/")) -> VolumeUsage? {
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
        ]
        guard let values = try? url.resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity, total > 0 else { return nil }
        let importantFree = values.volumeAvailableCapacityForImportantUsage.map(Int.init)
        let free = importantFree ?? values.volumeAvailableCapacity ?? 0
        return VolumeUsage(total: UInt64(total), free: UInt64(max(0, free)))
    }

    /// The non-overlapping overview categories that exist on this Mac.
    static func categories() -> [StorageCategory] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let library = home.appendingPathComponent("Library", isDirectory: true)

        // Home minus Library — kept separate so User Files + User Library don't
        // double count the home folder.
        let homeChildren = ((try? fm.contentsOfDirectory(
            at: home, includingPropertiesForKeys: nil, options: []
        )) ?? []).filter { $0.lastPathComponent != "Library" }

        let candidates: [StorageCategory] = [
            .init(kind: .userFiles, root: home, scanRoots: homeChildren, sizeBytes: 0),
            .init(kind: .userLibrary, root: library, scanRoots: [library], sizeBytes: 0),
            .init(kind: .applications,
                  root: URL(fileURLWithPath: "/Applications", isDirectory: true),
                  scanRoots: [URL(fileURLWithPath: "/Applications", isDirectory: true)],
                  sizeBytes: 0),
            .init(kind: .systemLibrary,
                  root: URL(fileURLWithPath: "/Library", isDirectory: true),
                  scanRoots: [URL(fileURLWithPath: "/Library", isDirectory: true)],
                  sizeBytes: 0),
        ]
        return candidates.filter { fm.fileExists(atPath: $0.root.path) }
    }

    static func size(of category: StorageCategory) -> UInt64 {
        category.scanRoots.reduce(0) { $0 + AppInventory.directorySize($1) }
    }

    /// The immediate children of `url`, sized later by the caller. Symlinks are
    /// skipped so the analyzer never follows a link out of the tree being
    /// measured (and never double-counts its target). Hidden entries are kept —
    /// `.Trash`, `.cache`, and friends are exactly where space hides.
    static func children(of url: URL) -> [StorageEntry] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: Array(keys), options: []
        ) else { return [] }

        return urls.compactMap { child in
            let values = try? child.resourceValues(forKeys: keys)
            if values?.isSymbolicLink == true { return nil }
            return StorageEntry(
                url: child,
                name: child.lastPathComponent,
                sizeBytes: 0,
                isDirectory: values?.isDirectory ?? false
            )
        }
    }
}
