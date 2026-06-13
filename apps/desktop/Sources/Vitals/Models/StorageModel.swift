import Foundation
import SwiftUI

/// State for the Storage tab: the boot volume's capacity (a cheap, instant
/// read taken on open) and — gated behind an explicit Analyze press — the
/// occupied-storage overview and the analyzer drill-down.
///
/// The split is deliberate: capacity is a single `statfs`-style read and costs
/// nothing, but measuring categories and folders walks the disk, so none of
/// that runs until the user asks. All filesystem work runs off the main actor;
/// this model only polls and publishes. Sizes arrive incrementally so a
/// multi-gigabyte tree never blocks the UI, `cancelScan()` stops everything in
/// flight, and both tasks cancel in `deinit`.
@MainActor
final class StorageModel: ObservableObject {
    @Published private(set) var volume: StorageAnalyzer.VolumeUsage?
    @Published private(set) var categories: [StorageCategory] = []
    @Published private(set) var isScanning = false
    /// True once Analyze has been pressed at least once — drives the idle
    /// prompt vs. the populated overview.
    @Published private(set) var hasRun = false

    // Analyzer
    /// Breadcrumb stack — the last element is the path being analyzed.
    @Published private(set) var path: [URL] = []
    @Published private(set) var entries: [StorageEntry] = []
    @Published private(set) var isAnalyzing = false

    private let inventory = AppInventory()
    private var categoryTask: Task<Void, Never>?
    private var analyzeTask: Task<Void, Never>?
    /// Carried across drill-downs so every navigation honours the setting that
    /// was in effect when the user pressed Analyze.
    private var includeHidden = true

    var currentRoot: URL? { path.last }

    /// The biggest entry's size, used to scale the proportional bars.
    var largestEntryBytes: UInt64 { entries.map(\.sizeBytes).max() ?? 0 }

    var categoriesTotal: UInt64 { categories.reduce(0) { $0 + ($1.sizeBytes ?? 0) } }

    /// Any disk-walking work in flight.
    var isBusy: Bool { isScanning || isAnalyzing }

    /// Cheap one-shot capacity read for tab open — no disk walk, no background
    /// task. Safe to call on every appearance; it only reads once.
    func loadVolume() {
        if volume == nil { volume = StorageAnalyzer.volumeUsage() }
    }

    /// The Analyze button: refresh capacity, measure the categories, and open
    /// the analyzer on the home folder. Everything that walks the disk lives
    /// behind this call — opening the tab never starts it on its own.
    func analyze(includeHidden: Bool) {
        guard !isScanning else { return }
        self.includeHidden = includeHidden
        hasRun = true
        volume = StorageAnalyzer.volumeUsage()
        scanCategories()
        navigate(to: FileManager.default.homeDirectoryForCurrentUser, reset: true)
    }

    /// Stops every in-flight scan at once — the user's explicit "stop running
    /// in the background" lever. Whatever was measured so far stays on screen.
    func cancelScan() {
        categoryTask?.cancel()
        analyzeTask?.cancel()
        isScanning = false
        isAnalyzing = false
    }

    private func scanCategories() {
        categoryTask?.cancel()
        isScanning = true
        categoryTask = Task { [weak self] in
            guard let self else { return }
            var scanned = StorageAnalyzer.categories()
            categories = scanned  // show the cards immediately; sizes follow
            for index in scanned.indices {
                if Task.isCancelled { isScanning = false; return }
                let category = scanned[index]
                let size = await Task.detached(priority: .utility) {
                    StorageAnalyzer.size(of: category)
                }.value
                if Task.isCancelled { isScanning = false; return }
                scanned[index].sizeBytes = size
                categories = scanned
            }
            isScanning = false
        }
    }

    // MARK: Analyzer navigation

    func openCategory(_ category: StorageCategory) {
        navigate(to: category.root, reset: true)
    }

    func drill(into entry: StorageEntry) {
        guard entry.isDirectory else { return }
        navigate(to: entry.url, reset: false)
    }

    func goUp() {
        guard path.count > 1 else { return }
        path.removeLast()
        if let root = path.last { runAnalyze(root) }
    }

    /// Jump to a breadcrumb at `index`, trimming everything deeper.
    func jump(to index: Int) {
        guard path.indices.contains(index) else { return }
        path = Array(path.prefix(index + 1))
        if let root = path.last { runAnalyze(root) }
    }

    private func navigate(to root: URL, reset: Bool) {
        if reset {
            path = [root]
        } else {
            path.append(root)
        }
        runAnalyze(root)
    }

    private func runAnalyze(_ root: URL) {
        analyzeTask?.cancel()
        isAnalyzing = true

        let children = StorageAnalyzer.children(of: root, includeHidden: includeHidden)
        // Show the structure alphabetically straight away; rows re-sort by size
        // as measurements land.
        entries = children.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let urls = children.map(\.url)

        guard !urls.isEmpty else {
            isAnalyzing = false
            return
        }

        analyzeTask = Task { [weak self] in
            guard let self else { return }
            var buffer: [URL: UInt64] = [:]
            for await (url, size) in inventory.sizes(for: urls) {
                if Task.isCancelled { return }
                buffer[url] = size
                if buffer.count >= 8 {
                    applyEntrySizes(buffer)
                    buffer.removeAll(keepingCapacity: true)
                }
            }
            applyEntrySizes(buffer)
            isAnalyzing = false
        }
    }

    /// Folds a batch of measured sizes in and re-sorts largest-first. Batching
    /// (rather than publishing each size) keeps the list from re-rendering once
    /// per child the way the apps list would.
    private func applyEntrySizes(_ sizes: [URL: UInt64]) {
        guard !sizes.isEmpty else { return }
        var updated = entries
        for index in updated.indices {
            if let size = sizes[updated[index].url] {
                updated[index].sizeBytes = size
            }
        }
        updated.sort { $0.sizeBytes > $1.sizeBytes }
        entries = updated
    }

    deinit {
        categoryTask?.cancel()
        analyzeTask?.cancel()
    }
}
