import AppKit

/// Composes a problem report to the developer: the user's description, a
/// diagnostic header, and the readable date-grouped log (`LogExport`) attached.
/// Uses the native mail composer (`NSSharingService`) so the user reviews and
/// sends from their own Mail account — no server, no credentials, and the logs
/// only leave the machine when they press Send.
@MainActor
enum ProblemReport {
    static let recipient = "99marafay@gmail.com"

    enum Outcome {
        case composed
        case noMailAccount(attachment: URL?)
        case failed(String)
    }

    /// Builds the diagnostic header. Uses the full live snapshot when a model is
    /// available (the Logs tab), else a static hardware/version header (Settings,
    /// where the model isn't in scope).
    static func diagnosticHeader(model: VitalsModel?, settings: AppSettings?) -> String {
        if let model, let settings {
            return DiagnosticSnapshot.text(model: model, settings: settings)
        }
        return """
        Vitals diagnostic header
        \(HardwareInfo.chipName) · \(HardwareInfo.osVersion) · up \(HardwareInfo.uptimeText)
        Version \(Updater.currentVersion) · session \(Log.session)
        Captured \(Date().formatted(date: .abbreviated, time: .standard))
        """
    }

    /// Opens the mail composer addressed to the developer with the log attached.
    /// `header` should come from `diagnosticHeader`. The heavy file render runs
    /// off-main; the composer is presented back on the main actor.
    static func compose(description: String, header: String) async -> Outcome {
        let attachment = await Task.detached(priority: .userInitiated) {
            LogExport.writeReport(header: header)
        }.value
        guard let attachment else {
            return .failed("There's nothing logged yet to send.")
        }

        guard let service = NSSharingService(named: .composeEmail) else {
            Log.error(.app, "mail composer service is unavailable")
            return .noMailAccount(attachment: attachment)
        }
        service.recipients = [recipient]
        service.subject = "Vitals problem report — v\(Updater.currentVersion)"

        let items: [Any] = [body(description: description, header: header), attachment]
        guard service.canPerform(withItems: items) else {
            Log.notice(.app, "no Mail account configured — falling back to manual send")
            return .noMailAccount(attachment: attachment)
        }
        service.perform(withItems: items)
        Log.notice(.app, "problem report composed (attachment \(attachment.lastPathComponent))")
        return .composed
    }

    /// Fallback when there's no Mail account: copy the write-up to the clipboard
    /// and reveal the attachment so the user can email it however they like.
    static func copyAndReveal(description: String, header: String, attachment: URL?) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(body(description: description, header: header), forType: .string)
        if let attachment {
            NSWorkspace.shared.activateFileViewerSelecting([attachment])
        }
    }

    private static func body(description: String, header: String) -> String {
        let note = description.trimmingCharacters(in: .whitespacesAndNewlines)
        return """
        \(note.isEmpty ? "(no description provided)" : note)

        ——— diagnostics ———
        \(header)

        The full diagnostic log is attached.
        """
    }
}
