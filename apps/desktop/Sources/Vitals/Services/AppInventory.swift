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

/// Finds the applications a user can uninstall. System software is excluded
/// by design: nothing under /System, no Apple bundle identifiers, and never
/// Vitals itself.
actor AppInventory {
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
            let worker = Task.detached(priority: .utility) {
                await withTaskGroup(of: (URL, UInt64).self) { group in
                    var pending = urls[...]
                    func addNext() {
                        guard !Task.isCancelled, let url = pending.popFirst() else { return }
                        group.addTask { (url, Self.directorySize(url)) }
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

    nonisolated static func directorySize(_ url: URL) -> UInt64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { _, _ in true }
        ) else {
            // A plain file (some leftovers are single plists).
            let size = (try? url.resourceValues(forKeys: keys).totalFileAllocatedSize) ?? 0
            return UInt64(size)
        }
        var total: UInt64 = 0
        for case let file as URL in enumerator {
            if Task.isCancelled { return total }
            guard let values = try? file.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
            total += UInt64(values.totalFileAllocatedSize ?? 0)
        }
        if total == 0 {
            let size = (try? url.resourceValues(forKeys: keys).totalFileAllocatedSize) ?? 0
            total = UInt64(size)
        }
        return total
    }
}
