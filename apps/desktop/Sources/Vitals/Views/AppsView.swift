import SwiftUI

/// The Applications section: every uninstallable app, multi-selectable, with a
/// leftover-aware uninstall.
struct AppsView: View {
    @Bindable var model: AppsModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    hero
                    listCard
                }
                .padding(20)
            }
            Divider()
                .opacity(0.5)
            footer
        }
        .onAppear {
            if model.apps.isEmpty { model.refresh() }
        }
        .sheet(item: $model.staged) { staged in
            UninstallConfirmationSheet(model: model, staged: staged)
                // Don't let a swipe/Esc dismiss the sheet mid-removal (the work keeps
                // running) or at the summary (a stale lastOutcome would reopen next time).
                // Only the in-sheet buttons drive it.
                .interactiveDismissDisabled(model.uninstallProgress != nil || model.lastOutcome != nil)
        }
    }

    // MARK: Hero

    private var hero: some View {
        PageHero(value: "\(model.apps.count) applications", subtitle: heroSubtitle) {
            searchField
            Picker("", selection: $model.sortOrder) {
                ForEach(AppsModel.SortOrder.allCases) { order in
                    Text(order.label).tag(order)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("Sort by name or size")
            Button {
                model.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .controlSize(.large)
            .disabled(model.isScanning)
            .help("Rescan applications")
        }
    }

    private var heroSubtitle: String {
        if model.isScanning { return "scanning /Applications…" }
        var parts: [String] = []
        if model.totalBytes > 0 { parts.append("\(formatBytes(model.totalBytes)) on disk") }
        if model.runningCount > 0 { parts.append("\(model.runningCount) running") }
        return parts.isEmpty ? "sizes are being measured" : parts.joined(separator: " · ")
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextField("Search", text: $model.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(.quaternary.opacity(0.5)))
        .frame(width: 200)
    }

    // MARK: App list

    @ViewBuilder
    private var listCard: some View {
        if model.apps.isEmpty && model.isScanning {
            LoadingStateView(
                title: "Scanning applications",
                message: "Reading /Applications and your user apps, then measuring sizes."
            )
        } else if let error = model.loadError {
            EmptyStateView(
                symbol: "exclamationmark.triangle.fill",
                tint: .orange,
                title: "Couldn't read your apps",
                message: error
            ) {
                Button { model.refresh() } label: {
                    Label("Try Again", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        } else if model.apps.isEmpty {
            EmptyStateView(
                symbol: "square.grid.2x2",
                tint: .purple,
                title: "Nothing to manage",
                message: "Vitals didn't find any applications in the scanned folders.",
                hints: [
                    .init(symbol: "folder", label: "/Applications"),
                    .init(symbol: "person.crop.square", label: "~/Applications"),
                ]
            ) {
                Button { model.refresh() } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
                .controlSize(.large)
            }
        } else if model.filteredApps.isEmpty {
            EmptyStateView(
                symbol: "magnifyingglass",
                tint: .blue,
                title: "No matches",
                message: "No apps match “\(model.searchText)”. Try a different name or bundle id."
            ) {
                Button { model.searchText = "" } label: {
                    Label("Clear Search", systemImage: "xmark.circle")
                }
                .controlSize(.large)
            }
        } else {
            LazyVStack(spacing: 0) {
                ForEach(Array(model.filteredApps.enumerated()), id: \.element.id) { index, app in
                    if index > 0 {
                        Divider()
                            .opacity(0.35)
                            .padding(.leading, 66)
                    }
                    AppRow(
                        app: app,
                        isSelected: app.protectedReason == nil && model.selection.contains(app.id),
                        toggle: { toggleSelection(app) }
                    )
                    .equatable()
                }
            }
            .insetCard()
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func toggleSelection(_ app: InstalledApp) {
        guard app.protectedReason == nil else { return }
        if model.selection.contains(app.id) {
            model.selection.remove(app.id)
        } else {
            model.selection.insert(app.id)
        }
    }

    private var allVisibleSelected: Bool {
        let visible = model.filteredApps
            .filter { $0.protectedReason == nil }
            .map(\.id)
        return !visible.isEmpty && visible.allSatisfy(model.selection.contains)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 12) {
            Toggle("Select all", isOn: Binding(
                get: { allVisibleSelected },
                set: { selectAll in
                    let visible = model.filteredApps
                        .filter { $0.protectedReason == nil }
                        .map(\.id)
                    if selectAll {
                        model.selection.formUnion(visible)
                    } else {
                        model.selection.subtract(visible)
                    }
                }
            ))
            .toggleStyle(.checkbox)
            .font(.callout)
            if !model.selection.isEmpty {
                Text("\(model.selection.count) selected · \(formatBytes(model.selectedBytes))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            Spacer()
            Button {
                model.prepareUninstall()
            } label: {
                if model.isPreparingUninstall {
                    Label("Scanning leftovers…", systemImage: "magnifyingglass")
                } else {
                    Label("Uninstall…", systemImage: "trash")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
            .disabled(model.selection.isEmpty || model.isPreparingUninstall)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

// MARK: - Row

private struct AppRow: View, Equatable {
    let app: InstalledApp
    let isSelected: Bool
    let toggle: () -> Void
    @State private var hovered = false

    static func == (lhs: AppRow, rhs: AppRow) -> Bool {
        lhs.app == rhs.app && lhs.isSelected == rhs.isSelected
    }

    var body: some View {
        Button {
            toggle()
        } label: {
            HStack(spacing: 11) {
                SelectionMark(selected: isSelected, size: 15)
                AppIconView(url: app.id, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(app.name)
                            .font(.system(size: 13, weight: .medium))
                        if app.isRunning {
                            Text("Running")
                                .font(.caption2.weight(.medium))
                                .capsuleTag(.green, fill: 0.16, horizontal: 5, vertical: 1)
                        }
                        if app.requiresAdmin && app.protectedReason == nil {
                            Image(systemName: "lock")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .help("Removing this app needs administrator rights")
                        }
                        if let protectedReason = app.protectedReason {
                            Image(systemName: "lock.fill")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .help("Protected: \(protectedReason)")
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
                    .font(.system(.callout, design: .rounded, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 86, alignment: .trailing)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(app.protectedReason != nil)
        .background(rowBackground)
        .onHover { hovered = $0 }
    }

    private var rowBackground: some View {
        Rectangle()
            .fill(
                isSelected
                    ? AnyShapeStyle(Color.accentColor.opacity(0.10))
                    : hovered ? AnyShapeStyle(.quaternary.opacity(0.4)) : AnyShapeStyle(.clear)
            )
    }
}
