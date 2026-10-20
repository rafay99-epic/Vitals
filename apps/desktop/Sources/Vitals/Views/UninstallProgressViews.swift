import SwiftUI

// MARK: - Live progress

/// Shown in place of the confirmation while the uninstall runs: the current
/// step, a bar (or spinner for one app), and per-app results as they finish.
struct UninstallProgressView: View {
    let progress: AppsModel.UninstallProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Uninstalling…", systemImage: "trash")
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 8) {
                Text(progress.phase.label)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .contentTransition(.identity)
                if progress.totalApps > 1 {
                    ProgressView(value: progress.fraction)
                        .progressViewStyle(.linear)
                    Text("\(progress.completedApps) of \(progress.totalApps) apps")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                }
            }

            if !progress.results.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(progress.results) { result in
                            resultRow(result)
                        }
                    }
                }
                .frame(minHeight: 60, maxHeight: 220)
            }
        }
        .padding(20)
    }

    private func resultRow(_ result: AppsModel.AppResult) -> some View {
        let style = Self.rowStyle(result.outcome)
        return HStack(spacing: 8) {
            AppIconView(url: result.id, size: 18)
            Text(result.name).fontWeight(.medium)
            Spacer()
            Text(style.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Image(systemName: style.symbol)
                .font(.system(size: 13))
                .foregroundStyle(style.tint)
        }
        .font(.callout)
    }

    /// View-layer formatting of a model `AppResult.Outcome` into icon + copy, so
    /// the model stays free of UI strings and byte formatting.
    private static func rowStyle(_ outcome: AppsModel.AppResult.Outcome) -> (symbol: String, tint: Color, detail: String) {
        switch outcome {
        case .trashed(let items, let bytes):
            return ("checkmark.circle.fill", .green, "\(items) item\(items == 1 ? "" : "s") · \(formatBytes(bytes))")
        case .homebrew:
            return ("checkmark.circle.fill", .green, "Removed with Homebrew")
        case .removedViaAdmin:
            return ("checkmark.circle.fill", .green, "Removed (system)")
        case .pendingAdmin:
            return ("lock.fill", .orange, "Needs your password")
        case .failed(let items):
            return ("exclamationmark.triangle.fill", .orange,
                    "\(items) item\(items == 1 ? "" : "s") couldn't be removed")
        }
    }
}

// MARK: - Finished summary

/// Replaces the progress view once the run completes, so the flow stays one
/// sheet (confirm, run, done).
struct UninstallSummaryView: View {
    let outcome: AppUninstaller.Outcome
    let onDone: () -> Void

    private var clean: Bool { outcome.failures.isEmpty && outcome.errorMessage == nil && !outcome.adminCancelled }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(clean ? "Uninstall finished" : "Uninstall incomplete",
                  systemImage: clean ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(clean ? Color.green : .orange)

            VStack(alignment: .leading, spacing: 6) {
                summaryRow("Moved to Trash", "\(outcome.trashed.count) items · \(formatBytes(outcome.freedBytes))")
                if outcome.systemRemoved > 0 {
                    summaryRow("Removed permanently", "\(outcome.systemRemoved) system files")
                }
                if outcome.caskUninstalled > 0 {
                    summaryRow("Homebrew", "\(outcome.caskUninstalled) uninstalled")
                }
                if !outcome.failures.isEmpty {
                    summaryRow("Couldn't remove", "\(outcome.failures.count) (in use or protected)", warn: true)
                }
                if let error = outcome.errorMessage {
                    summaryRow("System removal", error, warn: true)
                }
                if outcome.adminCancelled {
                    summaryRow("System files kept", "password cancelled", warn: true)
                }
            }

            HStack {
                Spacer()
                Button("Done", action: onDone)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
    }

    private func summaryRow(_ label: String, _ value: String, warn: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: warn ? "exclamationmark.circle" : "checkmark.circle")
                .font(.system(size: 12))
                .foregroundStyle(warn ? Color.orange : .secondary)
                .frame(width: 18)
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(.callout, design: .rounded, weight: .medium))
                .multilineTextAlignment(.trailing)
        }
        .font(.callout)
    }
}
