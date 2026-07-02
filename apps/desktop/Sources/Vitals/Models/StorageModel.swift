import Foundation
import SwiftUI

/// How the analyzer orders a folder's children. Size is the default (largest
/// first — the whole point of the tool); name gives a stable, browsable order
/// that doesn't reshuffle while sizes stream in.
enum StorageEntrySort: String, CaseIterable, Identifiable {
    case size, name
    var id: String { rawValue }
    var title: String { self == .size ? "Size" : "Name" }
}

/// State for the Storage tab: the boot volume's capacity (a cheap, instant
/// read taken on open) and — gated behind an explicit Analyze press — the
/// occupied-storage overview and the analyzer drill-down, which opens as a
/// browser page inside the panel (`isBrowsing`).
///
/// Performance shape (tuned for Apple silicon, but it helps everywhere):
/// every byte-counting walk runs *off* the main actor. The main actor only
/// receives finished, bounded snapshots — never a raw growing list and never a
/// sort. The analyzer holds at most `displayLimit` rows regardless of how many
/// children a folder has; ranking happens on a background thread and only the
/// visible top-N crosses back to the UI, at most a few times a second.
/// Every measured size lands in one session cache, so drilling into a category
/// the overview already measured is instant instead of a second disk walk.
/// `cancelScan()` stops everything in flight; all tasks cancel in `deinit`.
@MainActor
final class StorageModel: ObservableObject {
    /// The analyzer never publishes more than this many rows — the UI can't
    /// show more usefully, and it caps render cost on huge directories.
    static let displayLimit = 400

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

    // Analyzer browser
    /// True while the drill-down browser page is open (a category, insight, or
    /// whole-disk root was opened). The overview stays mounted underneath.
    @Published private(set) var isBrowsing = false
    /// Breadcrumb stack — the last element is the path being analyzed.
    @Published private(set) var path: [URL] = []
    /// Top `displayLimit` entries of the current folder, ordered by `sort`.
    @Published private(set) var entries: [StorageEntry] = []
    /// How many children the current folder actually has (entries is capped).
    @Published private(set) var entryTotal = 0
    @Published private(set) var isAnalyzing = false
    @Published private(set) var sort: StorageEntrySort = .size

    private let inventory = AppInventory()
    private var categoryTask: Task<Void, Never>?
    private var insightTask: Task<Void, Never>?
    private var analyzeTask: Task<Void, Never>?
    /// Carried across drill-downs so every navigation honours the setting that
    /// was in effect when the user pressed Analyze.
    private var includeHidden = true
    /// Every size measured this session, from any scan, keyed by path (URL
    /// representations differ between constructed and enumerated URLs).
    /// Re-listing a folder the categories (or a previous drill) already
    /// measured skips the walk. Cleared on Analyze for fresh numbers.
    private var sizeCache: [String: UInt64] = [:]

    var currentRoot: URL? { path.last }

    /// Largest entry's size, for scaling the bars. Entries are size-ordered by
    /// default; under name order the maximum can sit anywhere.
    var largestEntryBytes: UInt64 {
        sort == .size ? (entries.first?.sizeBytes ?? 0) : (entries.map(\.sizeBytes).max() ?? 0)
    }

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

    /// The Analyze button: refresh capacity and measure the categories and
    /// insights. Everything that walks the disk lives behind this call —
    /// opening the tab never starts it. Drilling into a folder is a separate,
    /// user-initiated navigation (`openCategory` and friends).
    func analyze(includeHidden: Bool) {
        guard !isBusy else { return }
        self.includeHidden = includeHidden
        hasRun = true
        sizeCache = [:]
        Log.debug(.storage, "storage analysis started (includeHidden: \(includeHidden))")
        refreshAccess()
        volume = StorageAnalyzer.volumeUsage()
        scanCategories()
        scanInsights()
        // A browser open on stale entries would show pre-re-analyze numbers.
        if isBrowsing, let root = path.last { runAnalyze(root) }
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
                sizeCache[url.path] = size
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
                sizeCache[url.path] = size
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

    /// Leave the browser page back to the overview. Stops the folder scan (the
    /// category/insight scans keep running — they belong to the overview).
    func closeBrowser() {
        analyzeTask?.cancel()
        isAnalyzing = false
        isBrowsing = false
        path = []
        entries = []
        entryTotal = 0
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

    /// Re-order the current listing. Cheap: the re-list hits the session size
    /// cache for everything already measured, so no second walk.
    func setSort(_ newSort: StorageEntrySort) {
        guard newSort != sort else { return }
        sort = newSort
        if let root = path.last { runAnalyze(root) }
    }

    private func navigate(to root: URL, reset: Bool) {
        if reset {
            path = [root]
        } else {
            path.append(root)
        }
        isBrowsing = true
        runAnalyze(root)
    }

    /// Lists, sizes, and ranks a folder's children entirely off the main actor,
    /// publishing only bounded, finished snapshots at most a few times a
    /// second. The main actor never sorts and never holds more than
    /// `displayLimit` rows, so even a directory with tens of thousands of
    /// entries can't stutter the UI. Sizes measured earlier this session are
    /// reused, so revisiting a measured folder is instant.
    private func runAnalyze(_ root: URL) {
        analyzeTask?.cancel()
        isAnalyzing = true
        entries = []
        entryTotal = 0
        let includeHidden = self.includeHidden
        let limit = Self.displayLimit
        let sort = self.sort
        let cached = sizeCache

        analyzeTask = Task.detached(priority: .utility) { [weak self, inventory] in
            let children = StorageAnalyzer.children(of: root, includeHidden: includeHidden)
            if Task.isCancelled { return }

            // First snapshot without waiting for the disk: cached sizes where
            // we have them, structure alone where we don't.
            var sizes: [URL: UInt64] = [:]
            for child in children {
                if let size = cached[child.url.path] { sizes[child.url] = size }
            }
            let initial = Self.ranked(children, sizes: sizes, limit: limit, sort: sort)
            let total = children.count
            await MainActor.run { [weak self] in
                guard let self, !Task.isCancelled else { return }
                self.entries = initial
                self.entryTotal = total
            }
            let unmeasured = children.map(\.url).filter { sizes[$0] == nil }
            guard !unmeasured.isEmpty else {
                await MainActor.run { [weak self] in self?.isAnalyzing = false }
                return
            }

            // Publish re-ranked snapshots on a clock, not per size — a folder
            // of thousands of small files would otherwise re-render the list
            // dozens of times a second.
            let clock = ContinuousClock()
            var lastPublish = clock.now
            for await (url, size) in inventory.sizes(for: unmeasured) {
                if Task.isCancelled { return }
                sizes[url] = size
                if clock.now - lastPublish >= .milliseconds(300) {
                    lastPublish = clock.now
                    let snapshot = Self.ranked(children, sizes: sizes, limit: limit, sort: sort)
                    let measured = Dictionary(uniqueKeysWithValues: sizes.map { ($0.key.path, $0.value) })
                    await MainActor.run { [weak self] in
                        guard let self, !Task.isCancelled else { return }
                        self.entries = snapshot
                        self.sizeCache.merge(measured) { _, new in new }
                    }
                }
            }
            let snapshot = Self.ranked(children, sizes: sizes, limit: limit, sort: sort)
            let measured = Dictionary(uniqueKeysWithValues: sizes.map { ($0.key.path, $0.value) })
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.entries = snapshot
                self.sizeCache.merge(measured) { _, new in new }
                self.isAnalyzing = false
            }
        }
    }

    /// Applies measured sizes and returns the top `limit` entries in the given
    /// order. Runs off the main actor. Internal (not private) so the ordering
    /// contract is test-locked.
    nonisolated static func ranked(
        _ children: [StorageEntry], sizes: [URL: UInt64], limit: Int, sort: StorageEntrySort
    ) -> [StorageEntry] {
        var sized = children
        for index in sized.indices {
            sized[index].sizeBytes = sizes[sized[index].url] ?? 0
        }
        switch sort {
        case .size:
            sized.sort { $0.sizeBytes > $1.sizeBytes }
        case .name:
            sized.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        return Array(sized.prefix(limit))
    }

    deinit {
        categoryTask?.cancel()
        insightTask?.cancel()
        analyzeTask?.cancel()
    }
}
