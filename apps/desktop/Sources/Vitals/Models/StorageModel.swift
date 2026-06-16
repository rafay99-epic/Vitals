import Foundation
import SwiftUI

/// State for the Storage tab: the boot volume's capacity (a cheap, instant
/// read taken on open) and — gated behind an explicit Analyze press — the
/// occupied-storage overview and the analyzer drill-down.
///
/// Performance shape (tuned for Apple silicon, but it helps everywhere):
/// every byte-counting walk runs *off* the main actor. The main actor only
/// receives finished, bounded snapshots — never a raw growing list and never a
/// sort. The analyzer holds at most `displayLimit` rows regardless of how many
/// children a folder has; ranking happens on a background thread and only the
/// visible top-N crosses back to the UI. Category and insight sizes are
/// measured concurrently (bounded), so a 12-core Mac isn't sizing one folder
/// at a time. `cancelScan()` stops everything in flight; all tasks cancel in
/// `deinit`.
@MainActor
final class StorageModel: ObservableObject {
    /// The analyzer never publishes more than this many rows — the UI can't
    /// show more usefully, and it caps render cost on huge directories.
    static let displayLimit = 200

    @Published private(set) var volume: StorageAnalyzer.VolumeUsage?
    /// True once a capacity read has been attempted (so a nil result reads as
    /// an error rather than "not loaded yet").
    @Published private(set) var volumeLoaded = false
    @Published private(set) var categories: [StorageCategory] = []
    @Published private(set) var insights: [StorageAnalyzer.StorageInsight] = []
    @Published private(set) var isScanning = false
    @Published private(set) var isScanningInsights = false
    /// Whether Vitals can read every folder. Without it the report is partial
    /// (protected folders read low); the view offers to fix that.
    @Published private(set) var hasFullDiskAccess = false
    /// True once Analyze has been pressed at least once — drives the idle
    /// prompt vs. the populated overview.
    @Published private(set) var hasRun = false

    // Analyzer
    /// Breadcrumb stack — the last element is the path being analyzed.
    @Published private(set) var path: [URL] = []
    /// Top `displayLimit` entries of the current folder, largest first.
    @Published private(set) var entries: [StorageEntry] = []
    /// How many children the current folder actually has (entries is capped).
    @Published private(set) var entryTotal = 0
    @Published private(set) var isAnalyzing = false

    private let inventory = AppInventory()
    private var categoryTask: Task<Void, Never>?
    private var insightTask: Task<Void, Never>?
    private var analyzeTask: Task<Void, Never>?
    /// Carried across drill-downs so every navigation honours the setting that
    /// was in effect when the user pressed Analyze.
    private var includeHidden = true

    var currentRoot: URL? { path.last }

    /// Largest entry's size, for scaling the bars. O(1): entries is already
    /// sorted largest-first, so the first element is the maximum.
    var largestEntryBytes: UInt64 { entries.first?.sizeBytes ?? 0 }

    var categoriesTotal: UInt64 { categories.reduce(0) { $0 + ($1.sizeBytes ?? 0) } }

    /// Any disk-walking work in flight.
    var isBusy: Bool { isScanning || isScanningInsights || isAnalyzing }

    /// Cheap one-shot capacity read for tab open — no disk walk, no background
    /// task. Safe to call on every appearance; it only reads once.
    func loadVolume() {
        guard volume == nil else { return }
        volume = StorageAnalyzer.volumeUsage()
        volumeLoaded = true
    }

    /// A capacity read was attempted and failed — the boot volume is somehow
    /// unreadable. Vanishingly rare, but handled gracefully.
    var volumeUnavailable: Bool { volumeLoaded && volume == nil }

    /// Re-probe Full Disk Access. Cheap; call on appear and after the user
    /// returns from System Settings so the banner reflects reality.
    func refreshAccess() {
        hasFullDiskAccess = StorageAnalyzer.hasFullDiskAccess()
    }

    /// The Analyze button: refresh capacity, measure the categories and
    /// insights, and open the analyzer on the home folder. Everything that
    /// walks the disk lives behind this call — opening the tab never starts it.
    func analyze(includeHidden: Bool) {
        guard !isBusy else { return }
        self.includeHidden = includeHidden
        hasRun = true
        Log.debug(.storage, "storage analysis started (includeHidden: \(includeHidden))")
        refreshAccess()
        volume = StorageAnalyzer.volumeUsage()
        scanCategories()
        scanInsights()
        navigate(to: FileManager.default.homeDirectoryForCurrentUser, reset: true)
    }

    /// Stops every in-flight scan at once — the user's explicit "stop running
    /// in the background" lever. Whatever was measured so far stays on screen.
    func cancelScan() {
        categoryTask?.cancel()
        insightTask?.cancel()
        analyzeTask?.cancel()
        isScanning = false
        isScanningInsights = false
        isAnalyzing = false
    }

    // MARK: Overview categories

    private func scanCategories() {
        categoryTask?.cancel()
        isScanning = true
        let template = StorageAnalyzer.categories()
        categories = template
        // Unique roots across all categories, sized concurrently (bounded) by
        // the shared sizer rather than one category at a time.
        let roots = Array(Set(template.flatMap { $0.scanRoots }))
        guard !roots.isEmpty else { isScanning = false; return }

        categoryTask = Task { [weak self] in
            guard let self else { return }
            var sizes: [URL: UInt64] = [:]
            for await (url, size) in inventory.sizes(for: roots) {
                if Task.isCancelled { isScanning = false; return }
                sizes[url] = size
                categories = Self.applyingCategorySizes(template, sizes)
            }
            categories = Self.applyingCategorySizes(template, sizes)
            isScanning = false
        }
    }

    /// Fills each category's size from measured roots. A category stays `nil`
    /// (its card keeps spinning) until *all* its roots are measured, so a
    /// stopped scan reads "Not measured" rather than a misleading partial.
    nonisolated private static func applyingCategorySizes(
        _ template: [StorageCategory], _ sizes: [URL: UInt64]
    ) -> [StorageCategory] {
        template.map { category in
            var category = category
            let measured = category.scanRoots.allSatisfy { sizes[$0] != nil }
            category.sizeBytes = measured
                ? category.scanRoots.reduce(0) { $0 + (sizes[$1] ?? 0) }
                : nil
            return category
        }
    }

    // MARK: Insights

    private func scanInsights() {
        insightTask?.cancel()
        isScanningInsights = true
        let list = StorageAnalyzer.insights()
        insights = list
        guard !list.isEmpty else { isScanningInsights = false; return }

        insightTask = Task { [weak self] in
            guard let self else { return }
            // Old Downloads needs date-filtered sizing; the rest are plain
            // directory sizes, routed through the shared concurrent sizer.
            for insight in list where insight.oldDownloadsOnly {
                if Task.isCancelled { isScanningInsights = false; return }
                let size = await Task.detached(priority: .utility) {
                    StorageAnalyzer.insightSize(insight)
                }.value
                if Task.isCancelled { isScanningInsights = false; return }
                applyInsightSize(insight.url, size)
            }
            let plain = list.filter { !$0.oldDownloadsOnly }.map(\.url)
            for await (url, size) in inventory.sizes(for: plain) {
                if Task.isCancelled { isScanningInsights = false; return }
                applyInsightSize(url, size)
            }
            isScanningInsights = false
        }
    }

    private func applyInsightSize(_ url: URL, _ size: UInt64) {
        if let index = insights.firstIndex(where: { $0.url == url }) {
            insights[index].sizeBytes = size
        }
    }

    // MARK: Analyzer navigation

    func openCategory(_ category: StorageCategory) {
        navigate(to: category.root, reset: true)
    }

    func openInsight(_ insight: StorageAnalyzer.StorageInsight) {
        navigate(to: insight.url, reset: true)
    }

    /// Drill into the whole boot volume from "/" — gated behind a setting and a
    /// confirmation in the UI because it walks system areas and can be slow.
    func analyzeWholeDisk() {
        navigate(to: URL(fileURLWithPath: "/", isDirectory: true), reset: true)
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

    /// Lists, sizes, and ranks a folder's children entirely off the main actor,
    /// publishing only bounded, finished snapshots. The main actor never sorts
    /// and never holds more than `displayLimit` rows, so even a directory with
    /// tens of thousands of entries can't stutter the UI.
    private func runAnalyze(_ root: URL) {
        analyzeTask?.cancel()
        isAnalyzing = true
        entries = []
        entryTotal = 0
        let includeHidden = self.includeHidden
        let limit = Self.displayLimit

        analyzeTask = Task.detached(priority: .utility) { [weak self, inventory] in
            let children = StorageAnalyzer.children(of: root, includeHidden: includeHidden)
            if Task.isCancelled { return }

            // Show structure immediately (alphabetical), capped to the limit.
            let initial = Array(
                children.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                    .prefix(limit)
            )
            let total = children.count
            await MainActor.run { [weak self] in
                guard let self, !Task.isCancelled else { return }
                self.entries = initial
                self.entryTotal = total
            }
            guard !children.isEmpty else {
                await MainActor.run { [weak self] in self?.isAnalyzing = false }
                return
            }

            var sizes: [URL: UInt64] = [:]
            var sincePublish = 0
            for await (url, size) in inventory.sizes(for: children.map(\.url)) {
                if Task.isCancelled { return }
                sizes[url] = size
                sincePublish += 1
                // Re-rank off-main on a throttle; publish only the visible top-N.
                if sincePublish >= 24 {
                    sincePublish = 0
                    let snapshot = Self.ranked(children, sizes: sizes, limit: limit)
                    await MainActor.run { [weak self] in
                        guard let self, !Task.isCancelled else { return }
                        self.entries = snapshot
                    }
                }
            }
            let snapshot = Self.ranked(children, sizes: sizes, limit: limit)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.entries = snapshot
                self.isAnalyzing = false
            }
        }
    }

    /// Applies measured sizes and returns the largest `limit` entries, sorted
    /// descending. Runs off the main actor.
    nonisolated private static func ranked(
        _ children: [StorageEntry], sizes: [URL: UInt64], limit: Int
    ) -> [StorageEntry] {
        var sized = children
        for index in sized.indices {
            sized[index].sizeBytes = sizes[sized[index].url] ?? 0
        }
        sized.sort { $0.sizeBytes > $1.sizeBytes }
        return Array(sized.prefix(limit))
    }

    deinit {
        categoryTask?.cancel()
        insightTask?.cancel()
        analyzeTask?.cancel()
    }
}
