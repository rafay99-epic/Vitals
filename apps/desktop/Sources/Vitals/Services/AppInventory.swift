import Foundation
import AppKit

/// One uninstallable application found on disk.
struct InstalledApp: Identifiable, Hashable {
    let id: URL          // the .app bundle URL
    let name: String
    let bundleID: String?
    let version: String?
    var sizeBytes: UInt64?
    var isRunning = false
    /// True when the bundle's parent directory isn't writable by this user,
    /// so moving it to the Trash would need elevated rights.
    let requiresAdmin: Bool
}

/// A counting gate over concurrent directory walks. Every sizing stream of one
/// `AppInventory` shares it, so however many streams are open at once (an
/// overview scan plus a drill-down plus a fallback), the *total* number of
/// walks touching the disk never exceeds `width` — streams queue behind each
/// other instead of multiplying.
actor SizingGate {
    private let width: Int
    private var inUse = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(width: Int) { self.width = width }

    func acquire() async {
        if inUse < width {
            inUse += 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty {
            inUse -= 1
        } else {
            // Hand the slot straight to the next waiter; inUse stays constant.
            waiters.removeFirst().resume()
        }
    }
}

/// Finds the applications a user can uninstall. System software is excluded
/// by design: nothing under /System, no Apple bundle identifiers, and never
/// Vitals itself.
actor AppInventory {
    /// Shared by every stream this inventory produces — see `SizingGate`.
    let gate = SizingGate(width: 6)
    nonisolated static let searchDirectories: [URL] = [
        URL(fileURLWithPath: "/Applications", isDirectory: true),
        URL(fileURLWithPath: "/Applications/Utilities", isDirectory: true),
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true),
    ]

    /// Apps Vitals refuses to list or touch.
    nonisolated static func isProtected(bundleID: String?, url: URL) -> Bool {
        if url.path.hasPrefix("/System") { return true }
        if url.lastPathComponent == "Vitals.app" { return true }
        guard let bundleID else { return false }
        if bundleID.hasPrefix("com.apple.") { return true }
        if let own = Bundle.main.bundleIdentifier, bundleID == own { return true }
        return false
    }

    func scan() -> [InstalledApp] {
        let fm = FileManager.default
        var seen = Set<URL>()
        var apps: [InstalledApp] = []

        for directory in Self.searchDirectories {
            guard let entries = try? fm.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            let parentWritable = fm.isWritableFile(atPath: directory.path)
            for url in entries where url.pathExtension == "app" {
                let resolved = url.resolvingSymlinksInPath()
                guard seen.insert(resolved).inserted else { continue }
                guard let bundle = Bundle(url: url) else { continue }
                let bundleID = bundle.bundleIdentifier
                guard !Self.isProtected(bundleID: bundleID, url: url) else { continue }

                let info = bundle.infoDictionary
                let name = (info?["CFBundleDisplayName"] as? String)
                    ?? (info?["CFBundleName"] as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                apps.append(InstalledApp(
                    id: url,
                    name: name,
                    bundleID: bundleID,
                    version: info?["CFBundleShortVersionString"] as? String,
                    requiresAdmin: !parentWritable
                ))
            }
        }
        return apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Streams (url, size) pairs as sizes finish computing, a few at a time so
    /// a folder full of multi-gigabyte apps doesn't saturate the disk. The
    /// worker stops promptly when the consumer goes away — no orphaned disk
    /// churn after a rescan or window close.
    nonisolated func sizes(for urls: [URL], concurrency: Int = 6) -> AsyncStream<(URL, UInt64)> {
        AsyncStream { continuation in
            let worker = Task.detached(priority: .utility) { [gate] in
                await withTaskGroup(of: (URL, UInt64).self) { group in
                    var pending = urls[...]
                    func addNext() {
                        guard !Task.isCancelled, let url = pending.popFirst() else { return }
                        group.addTask {
                            await gate.acquire()
                            let size = Self.directorySize(url)
                            await gate.release()
                            return (url, size)
                        }
                    }
                    for _ in 0..<concurrency { addNext() }
                    for await pair in group {
                        continuation.yield(pair)
                        addNext()
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in worker.cancel() }
        }
    }

    /// Like `sizes(for:)`, but each walk also accumulates subtotals for the
    /// `watching` paths that live inside the walked directory — so one pass
    /// over ~/Library can report Xcode DerivedData, Docker data, and friends
    /// as a byproduct instead of each needing its own walk. Every watched path
    /// under a yielded url gets an entry (0 if nothing was found there), so a
    /// yield is an authoritative measurement for its covered watches.
    nonisolated func sizesWithSubtotals(
        for urls: [URL], watching watchPaths: [String], concurrency: Int = 6
    ) -> AsyncStream<(URL, UInt64, [String: UInt64])> {
        AsyncStream { continuation in
            let worker = Task.detached(priority: .utility) { [gate] in
                await withTaskGroup(of: (URL, UInt64, [String: UInt64]).self) { group in
                    var pending = urls[...]
                    func addNext() {
                        guard !Task.isCancelled, let url = pending.popFirst() else { return }
                        let covered = watchPaths.filter {
                            $0 == url.path || $0.hasPrefix(url.path + "/")
                        }
                        group.addTask {
                            await gate.acquire()
                            let (size, subtotals) = Self.directorySize(url, accumulating: covered)
                            await gate.release()
                            return (url, size, subtotals)
                        }
                    }
                    for _ in 0..<concurrency { addNext() }
                    for await triple in group {
                        continuation.yield(triple)
                        addNext()
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in worker.cancel() }
        }
    }

    nonisolated static func directorySize(_ url: URL) -> UInt64 {
        directorySize(url, accumulating: []).total
    }

    /// One walk, two answers: the allocated size of `url`'s whole tree, plus a
    /// subtotal for every `watchPaths` entry (a path inside `url`) counting
    /// just the files under it. Watches always come back in the result — 0
    /// when nothing lives there — so callers can treat presence as "measured".
    nonisolated static func directorySize(
        _ url: URL, accumulating watchPaths: [String]
    ) -> (total: UInt64, subtotals: [String: UInt64]) {
        var subtotals = Dictionary(uniqueKeysWithValues: watchPaths.map { ($0, UInt64(0)) })
        // Precomputed once: the per-file loop below runs for every file in the
        // tree, and building "watch/" there would allocate per file per watch.
        let watches = watchPaths.map { (path: $0, prefix: $0 + "/") }
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { _, _ in true }
        ) else {
            // A plain file (some leftovers are single plists).
            let size = (try? url.resourceValues(forKeys: keys).totalFileAllocatedSize) ?? 0
            return (UInt64(size), subtotals)
        }
        var total: UInt64 = 0
        for case let file as URL in enumerator {
            if Task.isCancelled { return (total, subtotals) }
            guard let values = try? file.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
            let size = UInt64(values.totalFileAllocatedSize ?? 0)
            total += size
            if !watches.isEmpty {
                let path = file.path
                for watch in watches where path.hasPrefix(watch.prefix) {
                    subtotals[watch.path]! += size
                }
            }
        }
        if total == 0 {
            let size = (try? url.resourceValues(forKeys: keys).totalFileAllocatedSize) ?? 0
            total = UInt64(size)
        }
        return (total, subtotals)
    }
}
