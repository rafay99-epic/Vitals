import SwiftUI

/// A sheet for emailing the developer a problem report: opens a pre-addressed
/// mail draft with a diagnostic summary and reveals the log in Finder to attach.
/// Nothing leaves the machine until the user sends it.
struct ProblemReportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var detail = ""
    @State private var sending = false
    @State private var showNoMailHandler = false
    @State private var errorMessage: String?

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
                Text("Your mail app opens with a pre-filled message and the log is revealed in Finder to attach. The log includes app activity and file paths from your Mac (which contain your username). Nothing is sent until you press Send.")
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
                        Text("Email the Developer")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(sending)
            }
        }
        .padding(18)
        .frame(width: 460)
        .alert("No mail app found", isPresented: $showNoMailHandler) {
            Button("Copy Report") {
                ProblemReport.copyBody(description: detail)
                dismiss()
            }
            Button("Cancel", role: .cancel) { showNoMailHandler = false }
        } message: {
            Text("This Mac has no default mail app set up. Vitals revealed the log in Finder and can copy the report text so you can send it to \(ProblemReport.recipient) however you like.")
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
                Text("Email the developer your logs so the issue can be diagnosed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func send() async {
        sending = true
        defer { sending = false }
        let outcome = await ProblemReport.send(description: detail)
        switch outcome {
        case .opened:
            dismiss()
        case .noMailHandler:
            showNoMailHandler = true
        case .failed(let message):
            errorMessage = message
        }
    }
}
