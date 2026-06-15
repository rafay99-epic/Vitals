import SwiftUI
import AppKit

/// The Processes tab: a simple, app-grouped list of what's running with its
/// memory and CPU, and a one-click Quit on every row. The thing Activity
/// Monitor makes hard — "how much RAM is Brave using, and quit it" — in one place.
struct ProcessesView: View {
    @ObservedObject var model: ProcessesModel
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.animationsEnabled) private var animationsEnabled

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    hero
                    listCard
                }
                .padding(20)
            }
            // Pause live refreshes while scrolling — rebuilding the list
            // mid-scroll is what stutters. It catches up the instant it stops.
            .onScrollPhaseChange { _, phase in
                model.setScrolling(phase != .idle)
            }
            Divider().opacity(0.5)
            footer
        }
        .onAppear {
            model.includeSystem = settings.showSystemProcesses
            model.groupHelpers = settings.groupHelperProcesses
            model.start()
        }
        .onDisappear { model.stop() }
        // Warm the icon cache off the scroll path: without this, a row scrolling
        // into view fetches its app icon synchronously (NSWorkspace) and hitches.
        .onReceive(model.$groups) { groups in
            for group in groups where group.bundleURL != nil {
                _ = AppIconCache.icon(for: group.bundleURL!)
            }
        }
        .onChange(of: settings.showSystemProcesses) { _, show in
            model.includeSystem = show; model.refresh()
        }
        .onChange(of: settings.groupHelperProcesses) { _, group in
            model.groupHelpers = group; model.refresh()
        }
        .alert(item: $model.pendingQuit) { pending in
            quitAlert(pending)
        }
    }

    private func quitAlert(_ pending: ProcessesModel.PendingQuit) -> Alert {
        let force = pending.kind == .force
        return Alert(
            title: Text(force ? "Force quit \(pending.group.name)?" : "Quit \(pending.group.name)?"),
            message: Text(force
                ? "Force quitting kills it immediately — any unsaved changes will be lost."
                : "\(pending.group.name) will be asked to quit."),
            primaryButton: force
                ? .destructive(Text("Force Quit")) { model.confirmPending() }
                : .default(Text("Quit")) { model.confirmPending() },
            secondaryButton: .cancel { model.pendingQuit = nil }
        )
    }

    // MARK: Hero

    private var hero: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(model.appCount) apps")
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .contentTransition(.numericText())
                Text(heroSubtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            searchField
            Picker("", selection: $model.sortOrder) {
                ForEach(ProcessesModel.SortOrder.allCases) { order in
                    Text(order.label).tag(order)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("Sort by memory, CPU, or name")
            Button {
                model.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .controlSize(.large)
            .help("Refresh now")
        }
    }

    private var heroSubtitle: String {
        guard model.hasLoaded else { return "reading running processes…" }
        return "\(formatBytes(model.totalMemoryBytes)) in use · sorted by \(model.sortOrder.label.lowercased())"
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

    // MARK: List

    @ViewBuilder
    private var listCard: some View {
        if !model.hasLoaded {
            LoadingStateView(
                title: "Reading processes",
                message: "Vitals is measuring how much memory and CPU each app is using."
            )
        } else if model.filteredGroups.isEmpty && !model.searchText.isEmpty {
            EmptyStateView(
                symbol: "magnifyingglass",
                tint: .blue,
                title: "No matches",
                message: "Nothing running matches “\(model.searchText)”."
            ) {
                Button { model.searchText = "" } label: {
                    Label("Clear Search", systemImage: "xmark.circle")
                }
                .controlSize(.large)
            }
        } else {
            LazyVStack(spacing: 0) {
                ForEach(Array(model.filteredGroups.enumerated()), id: \.element.id) { index, group in
                    if index > 0 {
                        Divider().opacity(0.35).padding(.leading, 56)
                    }
                    ProcessRow(
                        group: group,
                        onQuit: { model.requestQuit(group, confirm: settings.confirmBeforeQuittingProcess) },
                        onForceQuit: { model.requestForceQuit(group) }
                    )
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.quaternary.opacity(0.3))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.separator.opacity(0.5), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            // GPU-accelerated reorder when the sort changes (lean mode snaps).
            .animation(animationsEnabled ? .spring(response: 0.32, dampingFraction: 0.86) : nil,
                       value: model.sortOrder)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: "cursorarrow.click")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Text("Right-click a row to Force Quit. System processes are hidden — turn them on in Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

// MARK: - Row

private struct ProcessRow: View {
    let group: ProcessesModel.Group
    let onQuit: () -> Void
    let onForceQuit: () -> Void
    @Environment(\.animationsEnabled) private var animationsEnabled
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 11) {
            icon
            VStack(alignment: .leading, spacing: 1) {
                Text(group.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if group.processCount > 1 {
                    Text("\(group.processCount) processes")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else if !group.isApp {
                    Text("Background process")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            metric(String(format: "%.0f%%", group.cpuPercent), width: 52)
            metric(formatBytes(group.memoryBytes), width: 84)
            quitControl
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .background(hovered ? AnyShapeStyle(.quaternary.opacity(0.4)) : AnyShapeStyle(.clear))
        .onHover { hovered = $0 }
        .contextMenu {
            if group.killable {
                Button("Quit", action: onQuit)
                Button("Force Quit", role: .destructive, action: onForceQuit)
            }
        }
    }

    private var icon: some View {
        Group {
            if let url = group.bundleURL {
                Image(nsImage: AppIconCache.icon(for: url))
                    .resizable()
                    .frame(width: 28, height: 28)
            } else {
                Image(systemName: "terminal")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.quaternary.opacity(0.5)))
            }
        }
    }

    private func metric(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .font(.system(.callout, design: .rounded, weight: .medium))
            .monospacedDigit()
            .contentTransition(.numericText())
            .foregroundStyle(.secondary)
            .frame(width: width, alignment: .trailing)
    }

    @ViewBuilder
    private var quitControl: some View {
        if group.killable {
            QuitButton(action: onQuit, name: group.name)
        } else {
            Image(systemName: "lock")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 64)
                .help("This is a system process — Vitals won't quit it")
        }
    }
}

/// A subtle "Quit" pill that turns red on hover, so quitting is one obvious click.
private struct QuitButton: View {
    let action: () -> Void
    let name: String
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text("Quit")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 56)
                .padding(.vertical, 4)
                .background(Capsule().fill(hovered ? AnyShapeStyle(Color.red.opacity(0.16)) : AnyShapeStyle(.quaternary.opacity(0.6))))
                .foregroundStyle(hovered ? AnyShapeStyle(Color.red) : AnyShapeStyle(.secondary))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help("Quit \(name)")
    }
}
