import Foundation
import SwiftUI

/// The Cleanup surface has four pages: the two classic depth-based cache sweeps
/// (Quick / Deep) plus per-project Developer junk and a Large-&-Old Files review.
/// Persisted by raw value in `@AppStorage("cleanupPage")`.
enum CleanupPage: String, CaseIterable, Identifiable {
    case quick, deep, developer, files

    var id: String { rawValue }
    var title: String {
        switch self {
        case .quick: return "Quick"
        case .deep: return "Deep"
        case .developer: return "Developer"
        case .files: return "Files"
        }
    }
}

/// Outcome of a Developer/Files sweep, surfaced to the view as an alert. Bytes
/// are the real freed amount the service confirmed (honesty over decoration).
struct ReclaimResult {
    var freedBytes: UInt64
    var failureCount: Int
}

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
    /// Time Machine local snapshots on the boot volume — reported, not deletable
    /// (macOS manages them and there's no honest byte size). nil when none / TM off.
    @Published private(set) var localSnapshots: Int?

    private var scanTask: Task<Void, Never>?

    var selectedCategories: [CleanupCategory] {
        categories.filter { selected.contains($0.kind) }
    }

    /// Selected categories whose removal is irreversible (e.g. device backups) —
    /// surfaced for a second, explicit confirmation before anything is deleted.
    var selectedDestructiveCategories: [CleanupCategory] {
        selectedCategories.filter { $0.kind.isDestructive && $0.sizeBytes > 0 }
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
        // Drop any selection that no longer exists at this depth. Pure enum
        // filtering — no filesystem IO on the main actor (the real scan runs
        // off-main below).
        selected.formIntersection(DiskCleaner.kinds(at: depth))

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
            // Report-only: Time Machine local snapshots (no deletion, no fake size).
            localSnapshots = await Task.detached(priority: .utility) { DiskCleaner.localSnapshotCount() }.value
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

    // MARK: - Developer junk

    @Published private(set) var devProjects: [DevJunkScanner.Project] = []
    @Published var devSelection: Set<URL> = []
    @Published private(set) var isDevScanning = false
    @Published private(set) var isDevCleaning = false
    @Published private(set) var hasDevRun = false
    @Published private(set) var lastDevResult: ReclaimResult?

    private var devScanTask: Task<Void, Never>?
    /// The roots the current listing was scanned from — reused verbatim when
    /// deleting so `DevJunkScanner`'s root check validates against the same set.
    private var devRoots: [URL] = []

    var selectedDevArtifacts: [DevJunkScanner.Artifact] {
        devProjects.flatMap { project in
            project.artifacts.filter { devSelection.contains($0.url) }
        }
    }
    var devSelectedBytes: UInt64 { selectedDevArtifacts.reduce(0) { $0 + $1.sizeBytes } }
    var devSelectedCount: Int { devSelection.count }
    var devTotalBytes: UInt64 { devProjects.reduce(0) { $0 + $1.totalBytes } }

    /// Projects that own at least one selected artifact, with the selected size —
    /// the list the confirmation names.
    var selectedDevProjects: [DevJunkScanner.Project] {
        devProjects.filter { project in
            project.artifacts.contains { devSelection.contains($0.url) }
        }
    }

    func isDevProjectSelected(_ project: DevJunkScanner.Project) -> Bool {
        !project.artifacts.isEmpty && project.artifacts.allSatisfy { devSelection.contains($0.url) }
    }

    func selectedBytes(in project: DevJunkScanner.Project) -> UInt64 {
        project.artifacts.filter { devSelection.contains($0.url) }.reduce(0) { $0 + $1.sizeBytes }
    }

    func toggleDevArtifact(_ url: URL) {
        if devSelection.contains(url) { devSelection.remove(url) } else { devSelection.insert(url) }
    }

    func toggleDevProject(_ project: DevJunkScanner.Project) {
        if isDevProjectSelected(project) {
            for artifact in project.artifacts { devSelection.remove(artifact.url) }
        } else {
            for artifact in project.artifacts { devSelection.insert(artifact.url) }
        }
    }

    /// Selects every artifact last modified before the cutoff. An unknown
    /// modification date never qualifies — we don't guess a project is stale.
    func selectStaleDev(olderThanDays days: Int = 7) {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) else { return }
        devSelection = Set(
            devProjects.flatMap(\.artifacts)
                .filter { ($0.modified ?? .distantFuture) < cutoff }
                .map(\.url)
        )
    }

    func clearDevSelection() { devSelection.removeAll() }

    /// Lists per-project developer artifacts (structure first, sizes streaming in
    /// off the main actor), mirroring `scan(depth:)`.
    func scanDev() {
        guard !isDevCleaning else { return }
        hasDevRun = true
        devScanTask?.cancel()
        isDevScanning = true
        let home = FileManager.default.homeDirectoryForCurrentUser

        // The task is itself detached so cancelling it (stopDevScan) reaches
        // Task.isCancelled inside the walk and between per-project measures; a
        // Task.detached nested in a main-actor task wouldn't inherit the cancel.
        // It hops to the main actor only to publish. A cancelled run returns
        // without clearing isDevScanning — only stopDevScan and natural
        // completion do, so a stale run can't hide a fresh scan's spinner.
        devScanTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let roots = DevJunkScanner.defaultRoots(home: home)
            var projects = DevJunkScanner.scan(roots: roots)
            if Task.isCancelled { return }
            let structure = projects
            await MainActor.run {
                self.devRoots = roots
                self.devProjects = structure  // structure now, sizes follow
                // Drop any selection whose artifact no longer exists.
                self.devSelection.formIntersection(Set(structure.flatMap(\.artifacts).map(\.url)))
            }

            for index in projects.indices {
                if Task.isCancelled { return }
                projects[index] = DevJunkScanner.measured(projects[index])
                if Task.isCancelled { return }
                let snapshot = projects
                await MainActor.run { self.devProjects = snapshot }
            }
            await MainActor.run { self.isDevScanning = false }
        }
    }

    func stopDevScan() {
        devScanTask?.cancel()
        isDevScanning = false
    }

    /// Permanently removes the selected artifacts (regenerable — the Trash would
    /// only waste space), credits the real freed bytes, then rescans.
    func cleanDev() {
        let targets = selectedDevArtifacts
        guard !targets.isEmpty, !isDevCleaning else { return }
        let roots = devRoots
        isDevCleaning = true

        Task { [weak self] in
            guard let self else { return }
            let result = await Task.detached(priority: .userInitiated) {
                DevJunkScanner.delete(targets, roots: roots)
            }.value
            lastDevResult = ReclaimResult(freedBytes: result.freedBytes, failureCount: result.failures.count)
            Log.notice(.cleanup, "developer clean freed \(ByteCountFormatter.string(fromByteCount: Int64(result.freedBytes), countStyle: .file))\(result.failures.isEmpty ? "" : ", \(result.failures.count) failed")")
            isDevCleaning = false
            devSelection.removeAll()
            scanDev()
        }
    }

    func dismissDevResult() { lastDevResult = nil }

    // MARK: - Large & old files

    @Published private(set) var largeFiles: [LargeFileScanner.Item] = []
    @Published var filesSelection: Set<URL> = []
    @Published private(set) var isFilesScanning = false
    @Published private(set) var isFilesCleaning = false
    @Published private(set) var hasFilesRun = false
    @Published private(set) var lastFilesResult: ReclaimResult?
    /// Minimum on-disk size to list; defaults to 100 MB.
    @Published var filesMinSize: UInt64 = 100 * 1024 * 1024
    /// Optional minimum age in days (nil = any age).
    @Published var filesMinAgeDays: Int?

    private var filesScanTask: Task<Void, Never>?

    var selectedFiles: [LargeFileScanner.Item] {
        largeFiles.filter { filesSelection.contains($0.url) }
    }
    var filesSelectedBytes: UInt64 { selectedFiles.reduce(0) { $0 + $1.sizeBytes } }
    var filesSelectedCount: Int { filesSelection.count }
    var filesTotalBytes: UInt64 { largeFiles.reduce(0) { $0 + $1.sizeBytes } }

    func toggleFile(_ url: URL) {
        if filesSelection.contains(url) { filesSelection.remove(url) } else { filesSelection.insert(url) }
    }

    func selectSuggested() {
        filesSelection = Set(largeFiles.filter(\.isSuggested).map(\.url))
    }

    func clearFilesSelection() { filesSelection.removeAll() }

    /// Lists big (and optionally old) personal files, largest first. Runs off the
    /// main actor; changing the size/age filters and rescanning is the view's job.
    func scanFiles() {
        guard !isFilesCleaning else { return }
        hasFilesRun = true
        filesScanTask?.cancel()
        isFilesScanning = true
        let home = FileManager.default.homeDirectoryForCurrentUser
        let filter = LargeFileScanner.Filter(minSizeBytes: filesMinSize, minAgeDays: filesMinAgeDays)

        // Detached so stopFilesScan's cancel reaches Task.isCancelled inside
        // LargeFileScanner.scan; a cancelled run returns without clearing
        // isFilesScanning (only stopFilesScan and natural completion do).
        filesScanTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let roots = LargeFileScanner.defaultRoots(home: home)
            let items = LargeFileScanner.scan(roots: roots, filter: filter, home: home)
            if Task.isCancelled { return }
            await MainActor.run {
                self.largeFiles = items
                self.filesSelection.formIntersection(Set(items.map(\.url)))
                self.isFilesScanning = false
            }
        }
    }

    func stopFilesScan() {
        filesScanTask?.cancel()
        isFilesScanning = false
    }

    /// Moves the selected files to the Trash (recoverable — these are the user's
    /// own files), credits the confirmed freed bytes, clears selection, rescans.
    func trashFiles() {
        let targets = selectedFiles
        guard !targets.isEmpty, !isFilesCleaning else { return }
        isFilesCleaning = true

        Task { [weak self] in
            guard let self else { return }
            let result = await Task.detached(priority: .userInitiated) {
                LargeFileScanner.trash(targets)
            }.value
            lastFilesResult = ReclaimResult(freedBytes: result.freedBytes, failureCount: result.failures.count)
            Log.notice(.cleanup, "trashed files freed \(ByteCountFormatter.string(fromByteCount: Int64(result.freedBytes), countStyle: .file))\(result.failures.isEmpty ? "" : ", \(result.failures.count) failed")")
            isFilesCleaning = false
            filesSelection.removeAll()
            scanFiles()
        }
    }

    func dismissFilesResult() { lastFilesResult = nil }

    deinit {
        scanTask?.cancel()
        devScanTask?.cancel()
        filesScanTask?.cancel()
    }
}
