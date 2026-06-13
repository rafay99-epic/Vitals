import Foundation
import SwiftUI

/// State for the Storage tab: the boot volume's capacity, the occupied-storage
/// overview (category sizes that stream in), and the analyzer — a drill-down of
/// the largest entries under whatever path the user is exploring.
///
/// All filesystem work runs off the main actor in detached tasks; this model
/// only polls and publishes. Sizes arrive incrementally so a multi-gigabyte
/// tree never blocks the UI, and both running scans cancel in `deinit`.
@MainActor
final class StorageModel: ObservableObject {
    @Published private(set) var volume: StorageAnalyzer.VolumeUsage?
    @Published private(set) var categories: [StorageCategory] = []
    @Published private(set) var isScanning = false

    // Analyzer
    /// Breadcrumb stack — the last element is the path being analyzed.
    @Published private(set) var path: [URL] = []
    @Published private(set) var entries: [StorageEntry] = []
    @Published private(set) var isAnalyzing = false

    private let inventory = AppInventory()
    private var categoryTask: Task<Void, Never>?
    private var analyzeTask: Task<Void, Never>?

    var currentRoot: URL? { path.last }

    /// The biggest entry's size, used to scale the proportional bars. Falls
    /// back to the analyzed total so a single huge folder doesn't peg the bar.
    var largestEntryBytes: UInt64 { entries.map(\.sizeBytes).max() ?? 0 }

    var categoriesTotal: UInt64 { categories.reduce(0) { $0 + $1.sizeBytes } }

    func refresh() {
        guard !isScanning else { return }
        isScanning = true
        volume = StorageAnalyzer.volumeUsage()

        categoryTask?.cancel()
        categoryTask = Task { [weak self] in
            guard let self else { return }
            var scanned = StorageAnalyzer.categories()
            categories = scanned  // show the cards immediately; sizes follow
            for index in scanned.indices {
                if Task.isCancelled { return }
                let category = scanned[index]
                let size = await Task.detached(priority: .utility) {
                    StorageAnalyzer.size(of: category)
                }.value
                if Task.isCancelled { return }
                scanned[index].sizeBytes = size
                categories = scanned
            }
            isScanning = false
        }

        // Open the analyzer on the home folder the first time through.
        if path.isEmpty {
            analyze(FileManager.default.homeDirectoryForCurrentUser, reset: true)
        }
    }

    // MARK: Analyzer navigation

    func openCategory(_ category: StorageCategory) {
        analyze(category.root, reset: true)
    }

    func drill(into entry: StorageEntry) {
        guard entry.isDirectory else { return }
        analyze(entry.url)
    }

    func goUp() {
        guard path.count > 1 else { return }
        path.removeLast()
        if let root = path.last { startAnalyze(root) }
    }

    /// Jump to a breadcrumb at `index`, trimming everything deeper.
    func jump(to index: Int) {
        guard path.indices.contains(index) else { return }
        path = Array(path.prefix(index + 1))
        if let root = path.last { startAnalyze(root) }
    }

    private func analyze(_ root: URL, reset: Bool = false) {
        if reset {
            path = [root]
        } else {
            path.append(root)
        }
        startAnalyze(root)
    }

    private func startAnalyze(_ root: URL) {
        analyzeTask?.cancel()
        isAnalyzing = true

        let children = StorageAnalyzer.children(of: root)
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
