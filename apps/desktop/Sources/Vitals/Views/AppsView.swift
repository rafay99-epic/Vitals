import SwiftUI
import AppKit

func formatBytes(_ bytes: UInt64) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
}

/// Process-wide icon cache: NSWorkspace lookups are not cheap, and list rows
/// re-render on every size update — without this, each render refetched every
/// App icon loading. The cache lookup is instant; the load itself
/// (`NSWorkspace.shared.icon(forFile:)`) touches disk + decodes the image, so
/// it runs off-main via `Task.detached` — a cold cache miss never blocks the
/// main thread, which is what held the Processes tab's first frame.
enum AppIconCache {
    private static let cache = NSCache<NSURL, NSImage>()

    /// Instant cache check — nil on miss. `NSCache` is thread-safe.
    static func cached(for url: URL) -> NSImage? {
        cache.object(forKey: url as NSURL)
    }

    /// Synchronous icon load — call off-main (`Task.detached`). `NSWorkspace`
    /// and `NSCache` are both thread-safe, so this needs no actor hop. Stores
    /// the result so the next `cached(for:)` hits.
    nonisolated static func loadIcon(for url: URL) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 32, height: 32)
        cache.setObject(icon, forKey: url as NSURL)
        return icon
    }
}

/// An app icon that loads off-main on a cache miss and shows a neutral
/// placeholder meanwhile. Shared by the Processes and Applications tabs so
/// neither blocks its first frame on `NSWorkspace.shared.icon(forFile:)`.
struct AppIconView: View {
    let url: URL
    let size: CGFloat
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable()
            } else {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(.quaternary.opacity(0.4))
            }
        }
        .frame(width: size, height: size)
        .task(id: url) {
            if let cached = AppIconCache.cached(for: url) {
                image = cached
            } else {
                image = await Task.detached(priority: .userInitiated) {
                    AppIconCache.loadIcon(for: url)
                }.value
            }
        }
    }
}

/// The Applications tab: every uninstallable app, multi-selectable, with a
/// leftover-aware uninstall that moves everything to the Trash.
struct AppsView: View {
    @ObservedObject var model: AppsModel
    /// True only while Applications is the visible tab. The view stays mounted,
    /// so the scan starts on activation rather than on appear.
    var isActive: Bool

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
        .onChange(of: isActive, initial: true) { _, active in
            if active && model.apps.isEmpty { model.refresh() }
        }
        .sheet(item: $model.staged) { staged in
            UninstallConfirmationSheet(model: model, staged: staged)
                // Don't let a swipe/Esc dismiss the sheet mid-removal (the work
                // keeps running) or at the summary (dismissing without Done would
                // strand a stale lastOutcome and reopen onto it next time) — only
                // the in-sheet buttons drive it.
                .interactiveDismissDisabled(model.uninstallProgress != nil || model.lastOutcome != nil)
        }
    }

    // MARK: Hero

    private var hero: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(model.apps.count) applications")
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .contentTransition(.numericText())
                Text(heroSubtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
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
                message: "Vitals didn't find any user-removable apps. System software and Apple apps are never listed here.",
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
                    AppRow(app: app, isSelected: selectionBinding(for: app))
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.quaternary.opacity(0.3))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.separator.opacity(0.5), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
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

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 12) {
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

private struct AppRow: View {
    let app: InstalledApp
    @Binding var isSelected: Bool
    @State private var hovered = false

    var body: some View {
        Button {
            isSelected.toggle()
        } label: {
            HStack(spacing: 11) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary))
                AppIconView(url: app.id, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(app.name)
                            .font(.system(size: 13, weight: .medium))
                        if app.isRunning {
                            Text("Running")
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(.green.opacity(0.16)))
                                .foregroundStyle(.green)
                        }
                        if app.requiresAdmin {
                            Image(systemName: "lock")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
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

// MARK: - Confirmation sheet

/// Shows exactly what will be moved to the Trash before anything happens.
private struct UninstallConfirmationSheet: View {
    @ObservedObject var model: AppsModel
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
        .frame(width: 560)
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
                Button(hasSystem ? "Uninstall" : "Move to Trash") { model.executeStagedUninstall() }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
            }
        }
        .padding(20)
    }

    private var introText: String {
        var text = "The app and the checked items below are removed — user files go to the Trash, so you can recover them. Uncheck anything you want to keep."
        if hasSystem {
            text += " Items marked 🔒 — system files and pkg-installed apps — are removed permanently and need your administrator password."
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
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(.yellow.opacity(0.18)))
                        .foregroundStyle(.yellow)
                }
                if staged.bundlesNeedingAdmin.contains(app.id) {
                    Label("admin · permanent", systemImage: "lock.fill")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(.orange.opacity(0.16)))
                        .foregroundStyle(.orange)
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

// MARK: - Live progress

/// Shown in place of the confirmation while the uninstall runs, so the work is
/// never invisible: the current step's label, a bar (or spinner for one app),
/// and a list that fills in per app as each finishes.
private struct UninstallProgressView: View {
    let progress: AppsModel.UninstallProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Uninstalling…", systemImage: "trash")
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 8) {
                // The phase label is the "is it stuck?" answer — always current.
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
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
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
        HStack(spacing: 8) {
            AppIconView(url: result.id, size: 18)
            Text(result.name).fontWeight(.medium)
            Spacer()
            Text(result.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Image(systemName: result.succeeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundStyle(result.succeeded ? Color.green : .orange)
        }
        .font(.callout)
    }
}

// MARK: - Finished summary

/// Replaces the progress once the run completes — the same outcome the old alert
/// showed, but inline so the flow is one continuous sheet (confirm → run → done).
private struct UninstallSummaryView: View {
    let outcome: AppUninstaller.Outcome
    let onDone: () -> Void

    private var clean: Bool { outcome.failures.isEmpty && outcome.errorMessage == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Uninstall finished", systemImage: clean ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
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
