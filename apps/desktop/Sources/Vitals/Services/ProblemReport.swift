import AppKit

/// Drafts a problem report via `mailto:` (the user's default mail handler) and
/// reveals the rendered log in Finder to attach. The user reviews and sends it;
/// nothing leaves the machine automatically.
@MainActor
enum ProblemReport {
    static let recipient = "99marafay@gmail.com"

    enum Outcome {
        case opened                     // mail draft opened, log revealed
        case noMailHandler(report: URL?)  // no default mail app
        case failed(String)
    }

    static func send(description: String) async -> Outcome {
        let header = compactHeader()
        let report = await Task.detached(priority: .userInitiated) { LogExport.writeReport(header: header) }.value
        let recent = await Task.detached(priority: .userInitiated) { LogExport.recentIssues(limit: 6) }.value

        let body = mailBody(description: description, recent: recent, reportName: report?.lastPathComponent)
        guard let url = mailtoURL(subject: "Vitals problem report — v\(Updater.currentVersion)", body: body) else {
            return .failed("Couldn't build the email.")
        }

        if let report { NSWorkspace.shared.activateFileViewerSelecting([report]) }

        guard NSWorkspace.shared.open(url) else {
            Log.notice(.app, "no default mail handler available for the problem report")
            return .noMailHandler(report: report)
        }
        Log.notice(.app, "problem report email drafted to \(recipient)")
        return .opened
    }

    /// Fallback when there's no mail handler: copy the body for pasting into webmail.
    static func copyBody(description: String) {
        let recent = LogExport.recentIssues(limit: 6)
        let body = mailBody(description: description, recent: recent, reportName: nil)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("To: \(recipient)\n\n\(body)", forType: .string)
    }

    // MARK: - Headers / body

    /// Short so the `mailto:` URL stays within practical limits.
    private static func compactHeader() -> String {
        "\(HardwareInfo.chipName) · \(HardwareInfo.osVersion) · Vitals \(Updater.currentVersion) · session \(Log.session)"
    }

    private static func mailBody(description: String, recent: [String], reportName: String?) -> String {
        var lines: [String] = []
        let note = description.trimmingCharacters(in: .whitespacesAndNewlines)
        lines.append(note.isEmpty ? "(no description provided)" : note)
        lines.append("")
        lines.append("— diagnostics —")
        lines.append(compactHeader())
        if !recent.isEmpty {
            lines.append("")
            lines.append("Recent issues:")
            lines.append(contentsOf: recent)
        }
        lines.append("")
        if let reportName {
            lines.append("Please attach the file just revealed in Finder (\(reportName)) — it has the full log.")
        }
        var body = lines.joined(separator: "\n")
        // mailto: URLs are limited to ~2000 chars in practice, and percent-encoding
        // inflates the body, so cap conservatively.
        if body.count > 1200 { body = String(body.prefix(1200)) + "\n…(truncated — see the attached log)" }
        return body
    }

    private static func mailtoURL(subject: String, body: String) -> URL? {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+?#")  // delimiters that confuse mailto parsers
        guard let subjectEncoded = subject.addingPercentEncoding(withAllowedCharacters: allowed),
              let bodyEncoded = body.addingPercentEncoding(withAllowedCharacters: allowed)
        else { return nil }
        return URL(string: "mailto:\(recipient)?subject=\(subjectEncoded)&body=\(bodyEncoded)")
    }
}
