import Foundation

/// Renders the JSONL log as readable text grouped by day, with signal-crash
/// backtraces appended verbatim at the end.
///
/// Blocking (reads and parses the whole log). Call off the main thread.
enum LogExport {
    /// Writes the report into `exports/`. Nil if the write failed.
    static func writeReport(header: String) -> URL? {
        let body = renderedText(header: header)
        guard !body.isEmpty else { return nil }
        let exports = DataHome.exportsDirectory
        do {
            try FileManager.default.createDirectory(at: exports, withIntermediateDirectories: true)
            let url = exports.appendingPathComponent("vitals-report-\(stamp.string(from: Date())).txt")
            try body.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            Log.error(.app, "couldn't write problem-report attachment", error: error)
            return nil
        }
    }

    static func renderedText(header: String) -> String {
        let (raw, unsorted) = LogFile.readAll()
        let entries = unsorted.sorted { $0.time < $1.time }

        var out = header
        out += "\n\n"

        if entries.isEmpty {
            out += "(no log entries)\n"
        } else {
            var lastDay = ""
            for entry in entries {
                let day = dayHeading.string(from: entry.time)
                if day != lastDay {
                    out += "\n──── \(day) ────\n"
                    lastDay = day
                }
                out += line(for: entry)
            }
        }

        let crashes = crashBlocks(in: raw)
        if !crashes.isEmpty {
            out += "\n──── CRASH BACKTRACES ────\n"
            out += crashes
        }
        return out
    }

    /// The last `limit` error/fault entries as one-liners, for the mail body.
    static func recentIssues(limit: Int) -> [String] {
        let issues = LogFile.readAll().entries.filter { $0.level >= .error }.suffix(limit)
        return issues.map { entry in
            var text = "\(clock.string(from: entry.time)) \(entry.level.badge) \(entry.category.title): \(entry.message)"
            if let error = entry.error { text += " — \(error.inline)" }
            return text
        }
    }

    private static func line(for entry: Log.Entry) -> String {
        var text = "\(clock.string(from: entry.time))  \(entry.level.badge)  "
        text += entry.category.title.padding(toLength: 10, withPad: " ", startingAt: 0)
        text += "  \(entry.message)  (\(entry.source.file):\(entry.source.line))\n"
        if let error = entry.error {
            text += "        ↳ \(error.inline)\n"
        }
        return text
    }

    /// The plain-text blocks between the C crash handler's markers.
    private static func crashBlocks(in raw: String) -> String {
        var blocks = ""
        var capturing = false
        for line in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.contains("VITALS-SIGNAL-CRASH") { capturing = true }
            if capturing { blocks += line + "\n" }
            if line.contains("END-CRASH") { capturing = false }
        }
        return blocks
    }

    private static let dayHeading: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, yyyy"
        return formatter
    }()

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter
    }()
}
