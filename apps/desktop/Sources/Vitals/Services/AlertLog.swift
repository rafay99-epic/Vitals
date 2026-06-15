import Foundation

/// One recorded alert firing, for the History tab's "Recent alerts" list.
struct AlertEvent: Identifiable {
    let time: Date
    let message: String
    var id: Date { time }
}

/// A tiny append-only log of fired alerts in the data home (`~/.vitals/alerts.log`),
/// so you can see what tripped and when — separate from the metric CSV. Lines are
/// `ISO8601<TAB>message`; tab-separated to avoid escaping the message's commas.
/// Best-effort: a failed write is silently dropped (an alert log is not critical
/// data), and parsing skips any malformed line.
enum AlertLog {
    static var fileURL: URL { DataHome.directory.appendingPathComponent("alerts.log") }

    static func record(message: String, at time: Date) {
        let line = isoFormatter.string(from: time) + "\t"
            + message.replacingOccurrences(of: "\n", with: " ") + "\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: fileURL)   // first write creates the file
        }
    }

    /// The most recent events, newest first.
    static func recent(limit: Int = 50) -> [AlertEvent] {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        let events = text.split(separator: "\n").compactMap(parse)
        return Array(events.suffix(limit).reversed())
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
