import SwiftUI

// MARK: - Confirmation sheet

/// Shows exactly what will be removed, and whether it goes to the Trash or is
/// deleted permanently, before anything happens.
struct UninstallConfirmationSheet: View {
    @Bindable var model: AppsModel
    let staged: AppsModel.StagedUninstall

    private var hasSystem: Bool {
        model.staged?.needsAdmin ?? staged.needsAdmin
    }

    var body: some View {
        Group {
            if let progress = model.uninstallProgress {
                UninstallProgressView(progress: progress)
            } else if let outcome = model.lastOutcome {
                UninstallSummaryView(outcome: outcome) { model.finishUninstall() }
            } else {
                confirmation
            }
        }
        // Fixed width + shared min height so the sheet doesn't resize between the
        // confirm / progress / summary states.
        .frame(width: 560)
        .frame(minHeight: 340, alignment: .top)
        .animation(.easeInOut(duration: 0.2), value: model.uninstallProgress == nil)
        .animation(.easeInOut(duration: 0.2), value: model.lastOutcome == nil)
    }

    private var confirmation: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(hasSystem ? "Uninstall completely?" : "Move to Trash?", systemImage: "trash")
                .font(.title3.weight(.semibold))
            Text(introText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if staged.apps.contains(where: \.isRunning) {
                noteLabel(
                    "Running apps will be quit first: \(staged.apps.filter(\.isRunning).map(\.name).joined(separator: ", "))",
                    "exclamationmark.triangle", .orange)
            }
            if !staged.casks.isEmpty {
                noteLabel("Homebrew apps are removed with brew uninstall --cask --zap (also clears their config & data).", "mug", .secondary)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(staged.apps) { app in
                        appSection(app)
                    }
                }
            }
            .frame(minHeight: 200, maxHeight: 360)

            HStack {
                Text("Total \(formatBytes(currentTotal))")
                    .font(.callout.weight(.medium))
                    .monospacedDigit()
                if hasSystem {
                    Label("admin", systemImage: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { model.staged = nil }
                    .keyboardShortcut(.cancelAction)
                Button(hasSystem || !staged.casks.isEmpty ? "Uninstall" : "Move to Trash") { model.executeStagedUninstall() }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
            }
        }
        .padding(20)
    }

    private var introText: String {
        var text = "The app and the checked items below are removed. User files go to the Trash, so you can recover them. Uncheck anything you want to keep."
        if hasSystem {
            text += " Items marked 🔒, system files and pkg-installed apps, are removed permanently and need your administrator password."
        }
        if !staged.casks.isEmpty {
            text += " Apps marked Homebrew are uninstalled by Homebrew, which removes them permanently."
        }
        return text
    }

    private func noteLabel(_ text: String, _ symbol: String, _ color: Color) -> some View {
        Label(text, systemImage: symbol)
            .font(.callout)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var currentTotal: UInt64 {
        // Read live from the model so unchecking items updates the total.
        model.staged?.totalBytes ?? staged.totalBytes
    }

    private func appSection(_ app: InstalledApp) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                AppIconView(url: app.id, size: 20)
                Text(app.name).fontWeight(.semibold)
                if staged.casks[app.id] != nil {
                    Text("Homebrew")
                        .font(.caption2.weight(.medium))
                        .capsuleTag(.yellow, horizontal: 5, vertical: 1)
                }
                if staged.bundlesNeedingAdmin.contains(app.id) {
                    Label("admin · permanent", systemImage: "lock.fill")
                        .font(.caption2.weight(.medium))
                        .capsuleTag(.orange, fill: 0.16, horizontal: 5, vertical: 1)
                        .help("Installed by a pkg (root-owned) — removed permanently with your password")
                }
                Spacer()
                Text(app.sizeBytes.map(formatBytes) ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(staged.leftovers[app.id] ?? []) { leftover in
                leftoverRow(leftover)
            }
            if (staged.leftovers[app.id] ?? []).isEmpty {
                Text("No leftover files found.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 28)
            }
            if let extensions = staged.systemExtensions[app.id], !extensions.isEmpty {
                Label(
                    "Has a system extension — remove it manually in System Settings ▸ General ▸ Login Items & Extensions; a restart may be needed.",
                    systemImage: "puzzlepiece.extension"
                )
                .font(.caption2)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 28)
            }
        }
    }

    private func leftoverRow(_ leftover: Leftover) -> some View {
        HStack(spacing: 8) {
            Toggle("Remove \(leftover.id.lastPathComponent)", isOn: Binding(
                get: { !(model.staged?.excluded.contains(leftover.id) ?? false) },
                set: { include in
                    if include {
                        model.staged?.excluded.remove(leftover.id)
                    } else {
                        model.staged?.excluded.insert(leftover.id)
                    }
                }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    if leftover.requiresAdmin {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                            .help("System file — removed permanently with admin rights")
                    }
                    Text(leftover.id.lastPathComponent)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Text("\(leftover.category.rawValue)\(leftover.requiresAdmin ? " · permanent" : "") · \(abbreviatedPath(leftover.id))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(formatBytes(leftover.sizeBytes))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 28)
    }

    private func abbreviatedPath(_ url: URL) -> String {
        url.deletingLastPathComponent().path
            .replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
    }
}
