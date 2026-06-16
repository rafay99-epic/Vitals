import Foundation
import SwiftUI

/// State for the Cleanup tab: category sizes and the clean operation.
///
/// Scanning is manual (like the Storage tab) — nothing walks the disk until
/// `scan(depth:)` is called. Sizes stream in off the main actor; `cancelScan()`
/// stops a scan in flight. Cleaning splits the selection: user-domain
/// categories are removed in-process, system categories run through one
/// administrator prompt via `PrivilegedShell` and a vetted, age-gated script.
@MainActor
final class CleanupModel: ObservableObject {
    @Published private(set) var categories: [CleanupCategory] = []
    @Published private(set) var depth: CleanDepth = .quick
    @Published private(set) var isScanning = false
    @Published private(set) var isCleaning = false
    @Published private(set) var hasRun = false
    @Published var selected: Set<CleanupCategory.Kind> = []
    @Published private(set) var lastResult: DiskCleaner.CleanResult?
    @Published private(set) var lastError: String?

    private var scanTask: Task<Void, Never>?

    var selectedCategories: [CleanupCategory] {
        categories.filter { selected.contains($0.kind) }
    }

    var selectedBytes: UInt64 {
        selectedCategories.reduce(0) { $0 + $1.sizeBytes }
    }

    var totalBytes: UInt64 {
        categories.reduce(0) { $0 + $1.sizeBytes }
    }

    /// Whether the current selection includes any system (admin) category.
    var selectionNeedsAdmin: Bool {
        selectedCategories.contains { $0.kind.requiresAdmin }
    }

    /// The manual trigger. Measures the categories for `depth`; opening the tab
    /// never starts this on its own (unless the auto-scan setting is on).
    func scan(depth: CleanDepth) {
        guard !isCleaning else { return }
        self.depth = depth
        hasRun = true
        Log.debug(.cleanup, "cleanup scan started (\(depth))")
        scanTask?.cancel()
        isScanning = true
        // Drop any selection that no longer exists at this depth.
        let kindsAtDepth = Set(DiskCleaner.scan(depth: depth).map(\.kind))
        selected.formIntersection(kindsAtDepth)

        scanTask = Task { [weak self] in
            guard let self else { return }
            var scanned = await Task.detached(priority: .userInitiated) { DiskCleaner.scan(depth: depth) }.value
            if Task.isCancelled { isScanning = false; return }
            categories = scanned  // show structure immediately, sizes follow
            for index in scanned.indices {
                if Task.isCancelled { isScanning = false; return }
                let category = scanned[index]
                let measured = await Task.detached(priority: .utility) { DiskCleaner.measured(category) }.value
                if Task.isCancelled { isScanning = false; return }
                scanned[index] = measured
                categories = scanned
            }
            isScanning = false
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        isScanning = false
    }

    func clean() {
        let targets = selectedCategories.filter { $0.sizeBytes > 0 }
        guard !targets.isEmpty, !isCleaning else { return }
        let userTargets = targets.filter { !$0.kind.requiresAdmin }
        let systemTargets = targets.filter { $0.kind.requiresAdmin }
        Log.debug(.cleanup, "clean started: \(userTargets.count) user, \(systemTargets.count) system categories")
        let currentDepth = depth
        isCleaning = true
        lastError = nil

        Task {
            var result = await Task.detached(priority: .userInitiated) { DiskCleaner.clean(userTargets) }.value

            // User-domain items the in-process pass couldn't delete (root-owned
            // cache files, permission-locked Trash) fall back to one admin pass —
            // the same recovery the uninstaller uses for blocked app bundles.
            if !result.failures.isEmpty,
               let script = DiskCleaner.userCleanFallbackScript(for: result.failures.map(\.url)) {
                do {
                    try await PrivilegedShell.runAsAdmin(
                        script,
                        prompt: "Vitals needs administrator access to remove protected items."
                    )
                    result.usedAdmin = true
                    // Honesty over decoration: credit only what's actually gone
                    // after the root pass; anything still present stays a failure.
                    let fm = FileManager.default
                    var stillFailed: [DiskCleaner.CleanResult.Failure] = []
                    for failure in result.failures {
                        if fm.fileExists(atPath: failure.url.path) {
                            stillFailed.append(failure)
                        } else {
                            result.freedBytes += failure.size
                            result.removedItems += 1
                        }
                    }
                    result.failures = stillFailed
                } catch let error as PrivilegedShell.AdminError {
                    if !error.cancelled {
                        Log.error(.cleanup, "privileged cache clean failed — \(error.message)")
                        lastError = error.message
                    }
                } catch {
                    Log.error(.cleanup, "privileged cache clean failed", error: error)
                    lastError = error.localizedDescription
                }
            }

            if !systemTargets.isEmpty {
                let script = DiskCleaner.systemCleanScript(for: Set(systemTargets.map(\.kind)))
                do {
                    try await PrivilegedShell.runAsAdmin(
                        script,
                        prompt: "Vitals needs administrator access to clean system files."
                    )
                    result.usedAdmin = true
                    // The script frees the age-eligible files we measured; credit
                    // that as the freed amount (best available estimate).
                    for target in systemTargets {
                        result.freedBytes += target.sizeBytes
                        result.removedItems += target.items.count
                    }
                } catch let error as PrivilegedShell.AdminError {
                    if !error.cancelled {
                        Log.error(.cleanup, "privileged system clean failed — \(error.message)")
                        lastError = error.message
                    }
                } catch {
                    Log.error(.cleanup, "privileged system clean failed", error: error)
                    lastError = error.localizedDescription
                }
            }

            lastResult = result
            Log.notice(.cleanup, "clean finished: \(result.removedItems) items, \(ByteCountFormatter.string(fromByteCount: Int64(result.freedBytes), countStyle: .file)) freed\(result.failures.isEmpty ? "" : ", \(result.failures.count) failed")")
            isCleaning = false
            selected.removeAll()
            scan(depth: currentDepth)
        }
    }

    func dismissResult() {
        lastResult = nil
    }

    func dismissError() {
        lastError = nil
    }

    deinit {
        scanTask?.cancel()
    }
}
