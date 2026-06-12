import SwiftUI
import AppKit

func formatBytes(_ bytes: UInt64) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
}

/// The Applications tab: every uninstallable app, multi-selectable, with a
/// leftover-aware uninstall that moves everything to the Trash.
struct AppsView: View {
    @StateObject private var model = AppsModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if model.apps.isEmpty && model.isScanning {
                Spacer()
                ProgressView("Scanning applications…")
                Spacer()
            } else {
                appList
            }
            Divider()
            footer
        }
        .onAppear { if model.apps.isEmpty { model.refresh() } }
        .sheet(item: $model.staged) { staged in
            UninstallConfirmationSheet(model: model, staged: staged)
        }
        .alert(
            "Uninstall finished",
            isPresented: Binding(get: { model.lastOutcome != nil }, set: { if !$0 { model.dismissOutcome() } }),
            presenting: model.lastOutcome
        ) { _ in
            Button("OK") { model.dismissOutcome() }
        } message: { outcome in
            if outcome.failures.isEmpty {
                Text("Moved \(outcome.trashed.count) items (\(formatBytes(outcome.freedBytes))) to the Trash.")
            } else {
                Text("Moved \(outcome.trashed.count) items to the Trash. \(outcome.failures.count) couldn't be removed: \(outcome.failures.map(\.url.lastPathComponent).joined(separator: ", "))")
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search applications", text: $model.searchText)
                .textFieldStyle(.plain)
            if model.isScanning {
                ProgressView().controlSize(.small)
            }
            Button {
                model.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Rescan applications")
            .disabled(model.isScanning)
        }
        .padding(12)
    }

    private var appList: some View {
        List {
            ForEach(model.filteredApps) { app in
                AppRow(app: app, isSelected: selectionBinding(for: app))
                    .contentShape(Rectangle())
                    .onTapGesture { selectionBinding(for: app).wrappedValue.toggle() }
            }
        }
        .listStyle(.inset)
    }

    private func selectionBinding(for app: InstalledApp) -> Binding<Bool> {
        Binding(
            get: { model.selection.contains(app.id) },
            set: { selected in
                if selected {
                    model.selection.insert(app.id)
                } else {
                    model.selection.remove(app.id)
                }
            }
        )
    }

    private var allVisibleSelected: Bool {
        let visible = model.filteredApps.map(\.id)
        return !visible.isEmpty && visible.allSatisfy(model.selection.contains)
    }

    private var footer: some View {
        HStack {
            Toggle("Select all", isOn: Binding(
                get: { allVisibleSelected },
                set: { selectAll in
                    let visible = model.filteredApps.map(\.id)
                    if selectAll {
                        model.selection.formUnion(visible)
                    } else {
                        model.selection.subtract(visible)
                    }
                }
            ))
            .toggleStyle(.checkbox)
            Text("\(model.apps.count) applications")
                .foregroundStyle(.secondary)
            Spacer()
            if !model.selection.isEmpty {
                Text("\(model.selection.count) selected")
                    .foregroundStyle(.secondary)
            }
            Button(role: .destructive) {
                model.prepareUninstall()
            } label: {
                if model.isPreparingUninstall {
                    Label("Scanning leftovers…", systemImage: "magnifyingglass")
                } else {
                    Label("Uninstall…", systemImage: "trash")
                }
            }
            .disabled(model.selection.isEmpty || model.isPreparingUninstall)
        }
        .font(.callout)
        .padding(12)
    }
}

private struct AppRow: View {
    let app: InstalledApp
    @Binding var isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: $isSelected)
                .labelsHidden()
                .toggleStyle(.checkbox)
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.id.path))
                .resizable()
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(app.name)
                    if app.isRunning {
                        Text("Running")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(.green.opacity(0.18)))
                            .foregroundStyle(.green)
                    }
                    if app.requiresAdmin {
                        Image(systemName: "lock")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .help("Removing this app needs administrator rights")
                    }
                }
                Text(app.bundleID ?? app.id.path)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if let version = app.version {
                Text(version)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Text(app.sizeBytes.map(formatBytes) ?? "—")
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }
}

/// Shows exactly what will be moved to the Trash before anything happens.
private struct UninstallConfirmationSheet: View {
    @ObservedObject var model: AppsModel
    let staged: AppsModel.StagedUninstall

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Move to Trash?", systemImage: "trash")
                .font(.title3.weight(.semibold))
            Text("The app and the leftover files below go to the Trash — nothing is deleted permanently. Uncheck anything you want to keep.")
                .font(.callout)
                .foregroundStyle(.secondary)

            if staged.apps.contains(where: \.isRunning) {
                Label(
                    "Running apps will be quit first: \(staged.apps.filter(\.isRunning).map(\.name).joined(separator: ", "))",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.callout)
                .foregroundStyle(.orange)
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
                Spacer()
                Button("Cancel") { model.staged = nil }
                    .keyboardShortcut(.cancelAction)
                Button("Move to Trash") { model.executeStagedUninstall() }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
            }
        }
        .padding(20)
        .frame(width: 560)
    }

    private var currentTotal: UInt64 {
        guard let staged = model.staged else { return staged.totalBytes }
        return staged.totalBytes
    }

    private func appSection(_ app: InstalledApp) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.id.path))
                    .resizable()
                    .frame(width: 20, height: 20)
                Text(app.name).fontWeight(.semibold)
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
        }
    }

    private func leftoverRow(_ leftover: Leftover) -> some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(
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
                Text(leftover.id.lastPathComponent)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(leftover.category.rawValue) · \(abbreviatedPath(leftover.id))")
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
