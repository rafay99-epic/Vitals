import Foundation
import AppKit

/// One application found on disk. Protected apps stay listed but can never be
/// selected for removal.
struct InstalledApp: Identifiable, Hashable {
    let id: URL          // the .app bundle URL
    let name: String
    let bundleID: String?
    let version: String?
    var sizeBytes: UInt64?
    var isRunning = false
    /// Non-nil when the app is visible but must never be selected or removed.
    let protectedReason: String?
    /// True when the bundle's parent directory isn't writable by this user,
    /// so moving it to the Trash would need elevated rights.
    let requiresAdmin: Bool
}

/// A counting gate shared by every sizing stream of one `AppInventory`, so the
/// total number of concurrent directory walks never exceeds `width`.
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

/// Finds top-level applications. Apple and Vitals bundles come back as
/// protected rows; the removal path refuses them.
actor AppInventory {
    let gate = SizingGate(width: 6)
    nonisolated static let searchDirectories: [URL] = [
        URL(fileURLWithPath: "/Applications", isDirectory: true),
        URL(fileURLWithPath: "/Applications/Utilities", isDirectory: true),
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true),
    ]

    /// Reason an app is visible but protected from selection/removal.
    nonisolated static func protectionReason(bundleID: String?, url: URL) -> String? {
        if url.path.hasPrefix("/System") { return "System app" }
        if url.lastPathComponent == "Vitals.app" { return "Vitals" }
        if let bundleID, bundleID.hasPrefix("com.syntaxlabtechnology.vitals") {
            return "Vitals channel"
        }
        if let bundleID, bundleID.hasPrefix("com.apple.") { return "Apple app" }
        if let own = Bundle.main.bundleIdentifier, bundleID == own { return "Vitals" }
        return nil
    }

    /// Apps Vitals refuses to touch.
    nonisolated static func isProtected(bundleID: String?, url: URL) -> Bool {
        protectionReason(bundleID: bundleID, url: url) != nil
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
                let protectedReason = Self.protectionReason(bundleID: bundleID, url: url)

                let info = bundle.infoDictionary
                let name = (info?["CFBundleDisplayName"] as? String)
                    ?? (info?["CFBundleName"] as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                apps.append(InstalledApp(
                    id: url,
                    name: name,
                    bundleID: bundleID,
                    version: info?["CFBundleShortVersionString"] as? String,
                    protectedReason: protectedReason,
                    requiresAdmin: !parentWritable
                ))
            }
        }
        return apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Streams (url, size) pairs as sizes finish, a few at a time so large apps
    /// don't saturate the disk. The worker is cancelled when the consumer goes
    /// away.
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

    /// Allocated size of `url`'s whole tree (or of `url` itself when it's a
    /// plain file). Stops early when the calling task is cancelled.
    nonisolated static func directorySize(_ url: URL) -> UInt64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        var total: UInt64 = 0
        if let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { _, _ in true }
        ) {
            for case let file as URL in enumerator {
                if Task.isCancelled { return total }
                guard let values = try? file.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
                total += UInt64(values.totalFileAllocatedSize ?? 0)
            }
        }
        if total == 0 {
            total = UInt64((try? url.resourceValues(forKeys: keys).totalFileAllocatedSize) ?? 0)
        }
        return total
    }
}
