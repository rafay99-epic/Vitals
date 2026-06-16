import SwiftUI

/// A sheet for sending the developer a problem report: the user explains what
/// happened, and Vitals attaches the diagnostic log to a pre-addressed email in
/// their Mail app. They review and send it themselves — the logs only leave the
/// machine when they press Send (the privacy heads-up says so).
struct ProblemReportView: View {
    /// Provided by the Logs tab (full live snapshot); nil from Settings (static
    /// header). See `ProblemReport.diagnosticHeader`.
    var model: VitalsModel?
    var settings: AppSettings?

    @Environment(\.dismiss) private var dismiss
    @State private var detail = ""
    @State private var sending = false
    @State private var fallback: Fallback?
    @State private var errorMessage: String?

    /// Captured when there's no Mail account, so the alert's actions can copy +
    /// reveal what would have been sent.
    private struct Fallback: Identifiable {
        let id = UUID()
        let header: String
        let attachment: URL?
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            VStack(alignment: .leading, spacing: 6) {
                Text("What happened?")
                    .font(.system(size: 12.5, weight: .medium))
                Text("Describe the problem — what you did, what you expected, and what went wrong.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $detail)
                    .font(.system(size: 12.5))
                    .frame(height: 120)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.quaternary.opacity(0.3)))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.separator.opacity(0.5)))
            }

            Label {
                Text("Your diagnostic log is attached. It includes app activity and file paths from your Mac (which contain your username). Nothing is sent until you press Send in Mail.")
            } icon: {
                Image(systemName: "lock.shield")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.quaternary.opacity(0.25)))

            HStack {
                Text("To: \(ProblemReport.recipient)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button {
                    Task { await send() }
                } label: {
                    if sending {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Compose Email")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(sending)
            }
        }
        .padding(18)
        .frame(width: 460)
        .alert("Couldn't open Mail", isPresented: Binding(get: { fallback != nil }, set: { if !$0 { fallback = nil } })) {
            Button("Copy & Reveal Log") {
                if let fallback {
                    ProblemReport.copyAndReveal(description: detail, header: fallback.header, attachment: fallback.attachment)
                }
                dismiss()
            }
            Button("Cancel", role: .cancel) { fallback = nil }
        } message: {
            Text("No email account is set up in Mail. Vitals copied your report to the clipboard and can reveal the log file so you can send it to \(ProblemReport.recipient) yourself.")
        }
        .alert("Couldn't build the report", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "envelope.badge")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.blue)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.blue.opacity(0.14)))
            VStack(alignment: .leading, spacing: 1) {
                Text("Report a Problem")
                    .font(.system(size: 14, weight: .semibold))
                Text("Send the developer your logs so the issue can be diagnosed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func send() async {
        sending = true
        defer { sending = false }
        let outcome = await ProblemReport.compose(
            description: detail,
            header: ProblemReport.diagnosticHeader(model: model, settings: settings)
        )
        switch outcome {
        case .composed:
            dismiss()
        case .noMailAccount(let attachment):
            fallback = Fallback(header: ProblemReport.diagnosticHeader(model: model, settings: settings), attachment: attachment)
        case .failed(let message):
            errorMessage = message
        }
    }
}
