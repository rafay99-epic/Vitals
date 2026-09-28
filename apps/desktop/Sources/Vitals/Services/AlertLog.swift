import Foundation

/// One recorded alert firing, for History's "Recent alerts" list.
struct AlertEvent: Identifiable {
    let time: Date
    let message: String
    var id: Date { time }
}

/// Fired alerts, stored in `HistoryDatabase`'s `alerts` table. Best-effort: an
/// alert log isn't critical data, so a failed write is dropped.
enum AlertLog {
    static func record(message: String, at time: Date) {
        HistoryDatabase.shared.recordAlert(message: message.replacingOccurrences(of: "\n", with: " "), at: time)
    }

    /// The most recent events, newest first.
    static func recent(limit: Int = 50) -> [AlertEvent] {
        HistoryDatabase.shared.recentAlerts(limit: limit)
    }
}
