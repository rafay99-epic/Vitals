import Foundation

/// Renders the diagnostic log into one **readable, date-grouped** text file for
/// sharing — the JSONL in `vitals.log` is faithful but not something you want to
/// read in an email. Entries are grouped under day headings, newest day last,
/// each line `HH:mm:ss.SSS  LVL  category  message (file:line)` with any error
/// detail on a continuation line. Raw signal-crash backtraces (the plain-text
/// blocks the C handler writes) are extracted and appended verbatim at the end.
///
/// Blocking (reads + parses the whole log) — call off the main thread.
enum LogExport {
    /// Writes the rendered report into `exports/` and returns its URL, or nil if
    /// there's nothing logged yet / the write failed.
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

    /// The full rendered report as a string.
    static func renderedText(header: String) -> String {
        let raw = [DataHome.logPrevious, DataHome.logFile]
            .compactMap { try? String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")

        var entries: [Log.Entry] = []
        for line in raw.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let entry = try? decoder.decode(Log.Entry.self, from: data) else { continue }
            entries.append(entry)
        }
        entries.sort { $0.time < $1.time }

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

    private static func line(for entry: Log.Entry) -> String {
        var text = "\(clock.string(from: entry.time))  \(entry.level.badge)  "
        text += entry.category.title.padding(toLength: 10, withPad: " ", startingAt: 0)
        text += "  \(entry.message)  (\(entry.source.file):\(entry.source.line))\n"
        if let error = entry.error {
            text += "        ↳ \(error.inline)\n"
        }
        return text
    }

    /// Pulls the plain-text crash blocks (between the C handler's markers) out of
    /// the raw log so they can be appended whole — they aren't JSON.
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

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

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
