import Foundation
import SwiftUI

/// The Cleanup pages: the depth-based cache sweeps (Quick / Deep) and
/// per-project Developer junk. Persisted in `@AppStorage("cleanupPage")`.
enum CleanupPage: String, CaseIterable, Identifiable {
    case quick, deep, developer

    var id: String { rawValue }
    var title: String {
        switch self {
        case .quick: return "Quick"
        case .deep: return "Deep"
        case .developer: return "Developer"
        }
    }
    /// SF Symbol shown beside each mode in the picker menu.
    var symbol: String {
        switch self {
        case .quick: return "sparkles"
        case .deep: return "sparkles.rectangle.stack"
        case .developer: return "hammer"
        }
    }
}

/// Outcome of a Developer sweep, surfaced to the view as an alert. Bytes
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
@Observable
final class CleanupModel {
    private(set) var categories: [CleanupCategory] = []
    private(set) var depth: CleanDepth = .quick
    private(set) var isScanning = false
    private(set) var isCleaning = false
    private(set) var hasRun = false
    var selected: Set<CleanupCategory.Kind> = []
    private(set) var lastResult: DiskCleaner.CleanResult?
    private(set) var lastError: String?
    /// Time Machine local snapshots on the boot volume — reported, not deletable
    /// (macOS manages them and there's no honest byte size). nil when none / TM off.
    private(set) var localSnapshots: Int?

    @ObservationIgnored private var scanTask: Task<Void, Never>?

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
            // Prune again against the categories the real scan actually returned —
            // the pre-scan prune above only knows the static superset, so a
            // conditional kind (e.g. .aiCaches) absent this run would otherwise
            // stay selected and counted in the footer with no visible row.
            selected.formIntersection(Set(scanned.map(\.kind)))
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

    private(set) var devProjects: [DevJunkScanner.Project] = []
    var devSelection: Set<URL> = []
    private(set) var isDevScanning = false
    private(set) var isDevCleaning = false
    private(set) var hasDevRun = false
    private(set) var lastDevResult: ReclaimResult?

    @ObservationIgnored private var devScanTask: Task<Void, Never>?
    /// The roots the current listing was scanned from — reused verbatim when
    /// deleting so `DevJunkScanner`'s root check validates against the same set.
    @ObservationIgnored private var devRoots: [URL] = []

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
                guard !Task.isCancelled else { return }
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
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    self.devProjects = snapshot
                }
            }
            await MainActor.run {
                guard !Task.isCancelled else { return }
                self.isDevScanning = false
            }
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

    deinit {
        scanTask?.cancel()
        devScanTask?.cancel()
    }
}
