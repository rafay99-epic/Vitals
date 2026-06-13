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
    /// `nil` until measured — distinguishes "not scanned yet / scan stopped"
    /// from a genuine zero, so a cancelled card never falsely reads "Empty".
    var sizeBytes: UInt64?

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
            .init(kind: .userFiles, root: home, scanRoots: homeChildren, sizeBytes: nil),
            .init(kind: .userLibrary, root: library, scanRoots: [library], sizeBytes: nil),
            .init(kind: .applications,
                  root: URL(fileURLWithPath: "/Applications", isDirectory: true),
                  scanRoots: [URL(fileURLWithPath: "/Applications", isDirectory: true)],
                  sizeBytes: nil),
            .init(kind: .systemLibrary,
                  root: URL(fileURLWithPath: "/Library", isDirectory: true),
                  scanRoots: [URL(fileURLWithPath: "/Library", isDirectory: true)],
                  sizeBytes: nil),
        ]
        return candidates.filter { fm.fileExists(atPath: $0.root.path) }
    }

    static func size(of category: StorageCategory) -> UInt64 {
        category.scanRoots.reduce(0) { $0 + AppInventory.directorySize($1) }
    }

    /// The immediate children of `url`, sized later by the caller. Symlinks are
    /// skipped so the analyzer never follows a link out of the tree being
    /// measured (and never double-counts its target). Hidden entries are kept
    /// by default — `.Trash`, `.cache`, and friends are exactly where space
    /// hides — but the caller can opt out.
    static func children(of url: URL, includeHidden: Bool = true) -> [StorageEntry] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        let options: FileManager.DirectoryEnumerationOptions = includeHidden ? [] : [.skipsHiddenFiles]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: Array(keys), options: options
        ) else { return [] }

        // At the volume root, drop firmware/virtual mounts and — crucially —
        // /Volumes, so a whole-disk scan never wanders into external or network
        // drives. Everything real (System, Library, Users, …) stays.
        let atVolumeRoot = url.path == "/"

        return urls.compactMap { child in
            if atVolumeRoot && volumeRootSkip.contains(child.lastPathComponent) { return nil }
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

    /// Top-level entries skipped when scanning from "/": device/firmware
    /// pseudo-directories and mount points that aren't part of this volume.
    private static let volumeRootSkip: Set<String> = [
        "dev", "Volumes", "Network", "net", "home", "cores", ".vol",
    ]

    // MARK: Full Disk Access

    /// macOS exposes no API to query — or to request — Full Disk Access, so we
    /// probe a file only an FDA-granted process can read: the system TCC
    /// database. Any failure (almost always EPERM) means we don't have it.
    /// Without FDA the analyzer still works; it just can't see into the folders
    /// macOS protects, so totals there read low.
    static func hasFullDiskAccess() -> Bool {
        let probe = URL(fileURLWithPath: "/Library/Application Support/com.apple.TCC/TCC.db")
        guard let handle = try? FileHandle(forReadingFrom: probe) else { return false }
        try? handle.close()
        return true
    }

    // MARK: Hidden-space insights

    /// A location that quietly accumulates disk usage — surfaced so the user
    /// can peek at it, never auto-deleted. Informed by Mole's insight catalog.
    struct StorageInsight: Identifiable {
        let name: String
        let detail: String
        let url: URL
        var sizeBytes: UInt64?
        /// Old Downloads is special: only files untouched for 90+ days count.
        let oldDownloadsOnly: Bool

        var id: URL { url }
    }

    /// The insight locations that exist on this Mac. These overlap the overview
    /// categories (they live inside Home / ~/Library), so they are deliberately
    /// kept out of the capacity bar — they're pointers, not a second breakdown.
    static func insights() -> [StorageInsight] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        func lib(_ component: String) -> URL { home.appendingPathComponent("Library/\(component)") }

        var found: [StorageInsight] = []
        func add(_ name: String, _ detail: String, _ url: URL, oldDownloadsOnly: Bool = false) {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return }
            found.append(.init(name: name, detail: detail, url: url, sizeBytes: nil, oldDownloadsOnly: oldDownloadsOnly))
        }

        add("iOS Backups", "Device backups under ~/Library/Application Support/MobileSync", lib("Application Support/MobileSync/Backup"))
        add("Old Downloads", "Files in ~/Downloads untouched for 90+ days", home.appendingPathComponent("Downloads"), oldDownloadsOnly: true)
        add("Xcode DerivedData", "Build products Xcode regenerates on the next build", lib("Developer/Xcode/DerivedData"))
        add("Xcode Simulators", "Installed Simulator runtimes and devices", lib("Developer/CoreSimulator/Devices"))
        add("Xcode Archives", "Saved app archives — your builds, not cache", lib("Developer/Xcode/Archives"))
        add("Docker Data", "Docker Desktop's disk image and data", lib("Containers/com.docker.docker/Data"))
        add("JetBrains Caches", "IDE caches and indexes", lib("Caches/JetBrains"))
        add("Spotify Cache", "Offline and streaming cache", lib("Application Support/Spotify/PersistentCache"))
        add("Homebrew Cache", "Downloaded bottles and old versions", lib("Caches/Homebrew"))
        add("System Logs", "App and system logs in ~/Library/Logs", lib("Logs"))
        add("Gradle Cache", "Downloaded build dependencies", home.appendingPathComponent(".gradle/caches"))
        add("CocoaPods Cache", "Downloaded pods", lib("Caches/CocoaPods"))
        add("pip Cache", "Python package cache", lib("Caches/pip"))
        return found
    }

    static func insightSize(_ insight: StorageInsight) -> UInt64 {
        insight.oldDownloadsOnly
            ? sizeOfFiles(in: insight.url, olderThanDays: 90)
            : AppInventory.directorySize(insight.url)
    }

    /// Sum of immediate entries (files and folders) last modified before the
    /// cutoff — so "Old Downloads" counts only what's genuinely stale.
    private static func sizeOfFiles(in directory: URL, olderThanDays days: Int) -> UInt64 {
        let fm = FileManager.default
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) else { return 0 }
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isDirectoryKey, .totalFileAllocatedSizeKey]
        guard let entries = try? fm.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: UInt64 = 0
        for entry in entries {
            guard let values = try? entry.resourceValues(forKeys: keys),
                  let modified = values.contentModificationDate, modified < cutoff else { continue }
            if values.isDirectory == true {
                total += AppInventory.directorySize(entry)
            } else {
                total += UInt64(values.totalFileAllocatedSize ?? 0)
            }
        }
        return total
    }
}
