import Foundation
import Combine

/// The in-app log console's data source: a bounded, newest-last ring of recent
/// `Log.Entry` values. It seeds itself from `LogFile` on launch (so the console
/// shows history, not just lines emitted since it opened) and then receives live
/// entries through the sink it registers with `Log`.
///
/// `@MainActor` because it publishes to SwiftUI; `Log` may emit from any thread,
/// so the sink hops to the main actor before appending.
@MainActor
final class LogStore: ObservableObject {
    @Published private(set) var entries: [Log.Entry] = []

    /// Caps memory for a long-running session; the on-disk file keeps the longer
    /// tail. ~2k lines is plenty to scroll and cheap to filter.
    private let maxEntries = 2_000

    init() {
        // Seed from disk off the main thread, then register for live entries.
        Task { [weak self] in
            let recent = await Task.detached(priority: .utility) {
                LogFile.shared.loadRecent(limit: 1_000)
            }.value
            guard let self else { return }
            // Live entries that arrived during the load go after the history.
            self.entries = recent + self.entries
            self.trim()
        }
        Log.setSink { [weak self] entry in
            Task { @MainActor in self?.append(entry) }
        }
    }

    private func append(_ entry: Log.Entry) {
        entries.append(entry)
        trim()
    }

    private func trim() {
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    /// Clears the in-memory view only. The on-disk `vitals.log` is untouched —
    /// "Reveal" still opens the full file.
    func clear() {
        entries.removeAll()
    }
}
