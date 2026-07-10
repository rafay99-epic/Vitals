import Foundation

/// The one safe filesystem walk that every "review the user's own files" surface
/// shares — the Large & Old Files review and the duplicate finder. Extracted so
/// those surfaces can't drift on the safety invariants that actually matter: the
/// walk never follows a symbolic link (neither a symlinked root nor a link met
/// mid-walk), skips hidden entries whole, treats a file package (`.app`,
/// `.photoslibrary`, …) as a single undescended item, refuses to enter the app's
/// own bundle or a `.vitals*` data directory, and stops descending past
/// `maxDepth`. Like every Service it is UI-free.
enum FileWalk {
    /// One thing the walk surfaces: a regular file or a file package. Directories
    /// are traversed, never yielded. `regularFileSize` is the honest allocated
    /// (on-disk) size for a regular file — the figure that matters for "space
    /// used" and reclaim; for a package it is 0 (the caller sizes the bundle whole
    /// if it cares). `logicalSize` is the file's byte length — the right key for
    /// *content* comparisons, since a sparse file and a full copy of the same
    /// bytes share a logical size but not an allocated one.
    struct Entry {
        let url: URL
        let isPackage: Bool
        let regularFileSize: UInt64
        let logicalSize: UInt64
        let modified: Date?
    }

    /// The largest depth the walk descends before stopping — a safety bound so a
    /// pathological tree can't spin the enumerator forever. User content rarely
    /// nests this deep.
    static let maxDepth = 8

    /// The user's content folders that actually exist on this Mac. A symlinked
    /// root is skipped so a redirected `~/Movies` never sends the walk out of the
    /// home folder (or double-counts its target).
    static func defaultContentRoots(home: URL) -> [URL] {
        let fm = FileManager.default
        let names = ["Downloads", "Documents", "Desktop", "Movies", "Music", "Pictures"]
        return names.compactMap { name in
            let url = home.appendingPathComponent(name, isDirectory: true)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return nil }
            if isSymlink(url) { return nil }
            return url
        }
    }

    /// True when `url` itself is a symbolic link (not merely something reached
    /// through one further down a walk).
    static func isSymlink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }

    /// A path-boundary-safe `hasPrefix`: true when `path` equals `base` or lies
    /// inside it, but not for an unrelated sibling that merely shares the string
    /// prefix (`<base>.backup`, `<base> 2`, …).
    static func isUnderOrEqual(_ path: String, base: String) -> Bool {
        path == base || path.hasPrefix(base + "/")
    }

    /// Paths the walk refuses to enter: the app's own bundle and anything under a
    /// `.vitals*` directory (its channel data dirs).
    static func isExcluded(_ url: URL, bundlePath: String) -> Bool {
        if !bundlePath.isEmpty && isUnderOrEqual(url.path, base: bundlePath) { return true }
        return url.pathComponents.contains { $0.hasPrefix(".vitals") }
    }

    /// Walks `roots` recursively and invokes `handle` for each regular file or
    /// package found, honouring every invariant above. `handle` returns `false`
    /// to stop the walk early (e.g. on cancellation), and enumerate then returns
    /// promptly; returning `true` continues.
    static func enumerate(roots: [URL], handle: (Entry) -> Bool) {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey, .isPackageKey, .isSymbolicLinkKey, .isRegularFileKey,
            .totalFileAllocatedSizeKey, .fileSizeKey, .contentModificationDateKey,
        ]
        let bundlePath = Bundle.main.bundlePath

        for root in roots {
            // Same never-follow-symlinks contract as defaultContentRoots: a caller
            // can hand us a symlinked root directly, so re-check it here too.
            if isSymlink(root) { continue }
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: Array(keys),
                // Packages are yielded but not descended into; hidden files/dirs
                // (incl. ~/.vitals*) are dropped whole.
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }
            ) else { continue }

            for case let url as URL in enumerator {
                guard let values = try? url.resourceValues(forKeys: keys) else { continue }
                if values.isSymbolicLink == true { continue }

                // Never touch the app's own bundle/data or a .vitals* directory.
                if isExcluded(url, bundlePath: bundlePath) {
                    if values.isDirectory == true { enumerator.skipDescendants() }
                    continue
                }

                let isPackage = values.isPackage == true
                if values.isDirectory == true && !isPackage {
                    // A plain directory: keep descending, but not past maxDepth.
                    if enumerator.level >= maxDepth { enumerator.skipDescendants() }
                    continue
                }

                let entry: Entry
                if isPackage {
                    entry = Entry(url: url, isPackage: true, regularFileSize: 0,
                                  logicalSize: 0, modified: values.contentModificationDate)
                } else if values.isRegularFile == true {
                    entry = Entry(url: url, isPackage: false,
                                  regularFileSize: UInt64(values.totalFileAllocatedSize ?? 0),
                                  logicalSize: UInt64(values.fileSize ?? 0),
                                  modified: values.contentModificationDate)
                } else {
                    continue  // sockets, fifos, and other non-files
                }
                if !handle(entry) { return }
            }
        }
    }
}
