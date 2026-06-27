import Foundation

/// One recorded alert firing, for the History tab's "Recent alerts" list.
struct AlertEvent: Identifiable {
    let time: Date
    let message: String
    var id: Date { time }
}

/// Fired alerts, so you can see what tripped and when. Stored in the history
/// `HistoryDatabase` (an `alerts` table) — this stays the view-facing API and
/// delegates there. Best-effort: a failed write is silently dropped (an alert
/// log is not critical data). The legacy `~/.vitals/logs/alerts.log` (tab-separated
/// `ISO8601<TAB>message`) is imported into the database once on upgrade; `parse`
/// still reads that format for the importer.
enum AlertLog {
    static func record(message: String, at time: Date) {
        HistoryDatabase.shared.recordAlert(message: message.replacingOccurrences(of: "\n", with: " "), at: time)
    }

    /// The most recent events, newest first.
    static func recent(limit: Int = 50) -> [AlertEvent] {
        HistoryDatabase.shared.recentAlerts(limit: limit)
    }

    static func parse(_ line: Substring) -> AlertEvent? {
        let parts = line.split(separator: "\t", maxSplits: 1)
        guard parts.count == 2, let time = isoFormatter.date(from: String(parts[0])) else { return nil }
        return AlertEvent(time: time, message: String(parts[1]))
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
