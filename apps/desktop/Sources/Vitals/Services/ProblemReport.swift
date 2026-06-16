import AppKit

/// Composes a problem report to the developer via a `mailto:` link: the user's
/// note plus a compact diagnostic header and recent issues go in the body, and
/// the full rendered log (`LogExport`) is revealed in Finder for the user to
/// attach. `mailto:` opens whatever the user set as their default mail handler
/// (so it works with Gmail-as-default, not only Apple Mail), and — like any mail
/// path — they review and press Send themselves. Nothing leaves the machine
/// automatically.
@MainActor
enum ProblemReport {
    static let recipient = "99marafay@gmail.com"

    enum Outcome {
        case opened                     // mail draft opened, log revealed
        case noMailHandler(report: URL?)  // no default mail app — fall back
        case failed(String)
    }

    /// Renders the log, reveals it, and opens a pre-filled mail draft.
    static func send(description: String, model: VitalsModel?, settings: AppSettings?) async -> Outcome {
        let header = diagnosticHeader(model: model, settings: settings)
        let report = await Task.detached(priority: .userInitiated) { LogExport.writeReport(header: header) }.value
        let recent = await Task.detached(priority: .userInitiated) { LogExport.recentIssues(limit: 6) }.value

        let body = mailBody(description: description, recent: recent, reportName: report?.lastPathComponent)
        guard let url = mailtoURL(subject: "Vitals problem report — v\(Updater.currentVersion)", body: body) else {
            return .failed("Couldn't build the email.")
        }

        // Reveal the rendered report first so it's waiting in Finder to attach.
        if let report { NSWorkspace.shared.activateFileViewerSelecting([report]) }

        guard NSWorkspace.shared.open(url) else {
            Log.notice(.app, "no default mail handler available for the problem report")
            return .noMailHandler(report: report)
        }
        Log.notice(.app, "problem report email drafted to \(recipient)")
        return .opened
    }

    /// Fallback when there's no mail handler: copy the body so the user can paste
    /// it into webmail; the report file is already revealed.
    static func copyBody(description: String, model: VitalsModel?, settings: AppSettings?) {
        let recent = LogExport.recentIssues(limit: 6)
        let body = mailBody(description: description, recent: recent, reportName: nil)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("To: \(recipient)\n\n\(body)", forType: .string)
    }

    // MARK: - Headers / body

    /// Full header for the attached report: the live snapshot when a model is
    /// available (the console), else a static hardware/version header (Settings).
    static func diagnosticHeader(model: VitalsModel?, settings: AppSettings?) -> String {
        if let model, let settings {
            return DiagnosticSnapshot.text(model: model, settings: settings)
        }
        return compactHeader()
    }

    /// One-liner for the mail body — kept short so the `mailto:` URL stays within
    /// practical length limits.
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
        // mailto: URLs are length-limited in practice; keep the body bounded and
        // let the attached report carry the full detail.
        if body.count > 1800 { body = String(body.prefix(1800)) + "\n…(truncated — see the attached log)" }
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
