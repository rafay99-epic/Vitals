import Foundation

/// Reviews big and old personal files under the user's content folders — the
/// "Large & Old Files" surface, the same idea as macOS Settings → Storage. Like
/// every other Service it is UI-free: it walks the filesystem and knows nothing
/// about the views that display its results.
///
/// **Trash-only contract.** These are the user's own documents, downloads, and
/// media — never regenerable cache. So deletion here is *always* recoverable:
/// `trash(_:)` moves items to the Trash via `FileManager.trashItem`, and nothing
/// in this file ever removes a file permanently (no `removeItem`, no `rm`). That
/// is the whole point of keeping this separate from `DiskCleaner`, which deletes
/// caches outright.
enum LargeFileScanner {
    /// One reviewable file (or file package) with the honest allocated size it
    /// occupies on disk. `isSuggested` marks the conservative subset we flag as
    /// obvious junk (see `isSuggested`); everything else is merely *listed* —
    /// large, but the user decides.
    struct Item: Identifiable, Hashable {
        let url: URL
        let name: String
        let sizeBytes: UInt64
        let modified: Date?
        let isSuggested: Bool

        var id: URL { url }
    }

    /// What counts as "large" (and optionally "old") for a scan.
    struct Filter: Equatable {
        /// Minimum on-disk size to list, e.g. 100 MB.
        var minSizeBytes: UInt64
        /// If set, only files last modified at least this many days ago are
        /// listed. `nil` lists any age.
        var minAgeDays: Int?
    }

    /// Outcome of a trash pass: bytes freed (credited only once the original
    /// path is confirmed gone) plus any items that couldn't be trashed, with a
    /// reason. Failures are recorded, never retried destructively.
    struct TrashResult {
        var freedBytes: UInt64
        var failures: [(url: URL, reason: String)]
    }

    /// The largest depth the walk descends before stopping — a safety bound so a
    /// pathological tree can't spin the enumerator forever. User content rarely
    /// nests this deep.
    private static let maxDepth = 8

    // MARK: Roots

    /// The user's content folders that actually exist on this Mac. Symlinked
    /// roots are skipped so a redirected `~/Movies` never sends the walk out of
    /// the home folder (or double-counts its target).
    static func defaultRoots(home: URL) -> [URL] {
        let fm = FileManager.default
        let names = ["Downloads", "Documents", "Desktop", "Movies", "Music", "Pictures"]
        return names.compactMap { name in
            let url = home.appendingPathComponent(name, isDirectory: true)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return nil }
            if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { return nil }
            return url
        }
    }

    // MARK: Scanning

    /// Walks `roots` (recursively, never following symlinks, skipping hidden
    /// entries entirely) and returns the files at or above `filter.minSizeBytes`,
    /// ranked by size descending and capped at `limit`. File packages (`.app`
    /// bundles, `.photoslibrary`, `.imovielibrary`, …) count as **one** item,
    /// sized whole and never descended into — the user thinks of them as a single
    /// thing. Regular files are sized by their allocated bytes, the honest figure
    /// (`AppInventory.directorySize` / `totalFileAllocatedSize`), so sparse and
    /// cloud-placeholder files count what they really occupy.
    static func scan(
        roots: [URL],
        filter: Filter,
        home: URL,
        now: Date = Date(),
        limit: Int = 400
    ) -> [Item] {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey, .isPackageKey, .isSymbolicLinkKey, .isRegularFileKey,
            .totalFileAllocatedSizeKey, .contentModificationDateKey,
        ]
        // Age gate: files must be older than this instant to qualify.
        let cutoff = filter.minAgeDays.flatMap {
            Calendar.current.date(byAdding: .day, value: -$0, to: now)
        }
        let bundlePath = Bundle.main.bundlePath

        var items: [Item] = []
        for root in roots {
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: Array(keys),
                // Packages are yielded but not descended into; hidden files/dirs
                // (incl. ~/.vitals*) are dropped whole.
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }
            ) else { continue }

            for case let url as URL in enumerator {
                if Task.isCancelled { return finish(items, limit: limit) }
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

                // A single reviewable thing: a package (sized whole) or a file.
                let size: UInt64
                if isPackage {
                    size = AppInventory.directorySize(url)
                } else if values.isRegularFile == true {
                    size = UInt64(values.totalFileAllocatedSize ?? 0)
                } else {
                    continue  // sockets, fifos, and other non-files
                }

                guard size >= filter.minSizeBytes else { continue }
                let modified = values.contentModificationDate
                if let cutoff {
                    guard let modified, modified < cutoff else { continue }
                }
                items.append(Item(
                    url: url,
                    name: url.lastPathComponent,
                    sizeBytes: size,
                    modified: modified,
                    isSuggested: isSuggested(url: url, modified: modified, home: home, now: now)
                ))
            }
        }
        return finish(items, limit: limit)
    }

    /// Rank by size descending and cap at `limit`.
    private static func finish(_ items: [Item], limit: Int) -> [Item] {
        let sorted = items.sorted { $0.sizeBytes > $1.sizeBytes }
        return limit < sorted.count ? Array(sorted.prefix(limit)) : sorted
    }

    /// Paths the scan refuses to enter: the app's own bundle/data and anything
    /// under a `.vitals*` directory (its channel data dirs).
    private static func isExcluded(_ url: URL, bundlePath: String) -> Bool {
        if !bundlePath.isEmpty && url.path.hasPrefix(bundlePath) { return true }
        return url.pathComponents.contains { $0.hasPrefix(".vitals") }
    }

    // MARK: Suggestions

    /// Whether to conservatively flag `url` as obvious junk worth suggesting for
    /// removal. **Deliberately narrow** — false positives here nudge the user to
    /// trash a real file, so the rules are exactly these and nothing more. A file
    /// qualifies only when it lives inside `~/Downloads` (directly or nested)
    /// AND one of:
    ///   a. an installer/image (`.dmg .pkg .iso .xip`) last touched over 90 days ago;
    ///   b. a dead partial download (`.crdownload .download .part`) — any age;
    ///   c. a stale archive (`.zip .gz .tgz .tar`) last touched over 180 days ago.
    /// Everything else is `false`: a huge `.mp4` in Movies is *listed* but never
    /// suggested. An unknown modification date never satisfies an age-gated rule.
    static func isSuggested(url: URL, modified: Date?, home: URL, now: Date = Date()) -> Bool {
        let downloads = home.appendingPathComponent("Downloads", isDirectory: true)
            .standardizedFileURL.path
        // Directly inside or anywhere under ~/Downloads.
        guard url.standardizedFileURL.path.hasPrefix(downloads + "/") else { return false }

        func olderThan(_ days: Int) -> Bool {
            guard let modified else { return false }
            return now.timeIntervalSince(modified) > Double(days) * 86_400
        }

        switch url.pathExtension.lowercased() {
        case "crdownload", "download", "part":
            return true
        case "dmg", "pkg", "iso", "xip":
            return olderThan(90)
        case "zip", "gz", "tgz", "tar":
            return olderThan(180)
        default:
            return false
        }
    }

    // MARK: Trashing

    /// Moves each item to the Trash — the only deletion this type performs, and a
    /// recoverable one (these are the user's personal files). After trashing we
    /// confirm the original path is gone before crediting its bytes; anything
    /// that fails is recorded with a reason and left in place, never force-deleted.
    static func trash(_ items: [Item]) -> TrashResult {
        let fm = FileManager.default
        var result = TrashResult(freedBytes: 0, failures: [])
        for item in items {
            do {
                try fm.trashItem(at: item.url, resultingItemURL: nil)
                if fm.fileExists(atPath: item.url.path) {
                    result.failures.append((url: item.url, reason: "still present after trashing"))
                } else {
                    result.freedBytes += item.sizeBytes
                }
            } catch {
                Log.notice(.cleanup, "couldn't trash \(item.name)", error: error)
                result.failures.append((url: item.url, reason: error.localizedDescription))
            }
        }
        return result
    }
}
