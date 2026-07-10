import SwiftUI
import AppKit
import QuickLook

/// The Cleanup → Duplicates page: sets of byte-for-byte identical files, with the
/// redundant copies reclaimable to the Trash (recoverable — they're the user's own
/// files). Display-only; every filesystem call goes through `CleanupModel` /
/// `DuplicateScanner`. Mirrors `CleanupFilesPage`'s shape so the Cleanup pages read
/// as one surface.
struct CleanupDuplicatesPage: View {
    @ObservedObject var model: CleanupModel
    @State private var confirming = false
    @State private var previewURL: URL?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    hero
                    filterRow
                    if !model.hasDupRun {
                        idlePrompt
                    } else if !model.isDupScanning && model.duplicateGroups.isEmpty {
                        emptyState
                    } else {
                        toolbar
                        groupList
                    }
                }
                .padding(20)
            }
            .quickLookPreview($previewURL)
            Divider()
                .opacity(0.5)
            footer
        }
        .onChange(of: model.dupMinSize) { _, _ in if model.hasDupRun { model.scanDuplicates() } }
        .confirmationDialog(
            "Move \(formatBytes(model.dupSelectedBytes)) to the Trash?",
            isPresented: $confirming,
            titleVisibility: .visible
        ) {
            Button("Move to Trash") { model.trashDuplicates() }
        } message: {
            Text("\(model.dupSelectedCount) file\(model.dupSelectedCount == 1 ? "" : "s") will be moved to the Trash. You can recover them from the Finder until you empty it.")
        }
        .alert(
            "Moved to Trash",
            isPresented: Binding(get: { model.lastDupResult != nil }, set: { if !$0 { model.dismissDupResult() } }),
            presenting: model.lastDupResult
        ) { _ in
            Button("OK") { model.dismissDupResult() }
        } message: { result in
            if result.failureCount == 0 {
                Text("Freed \(formatBytes(result.freedBytes)) — recoverable from the Trash.")
            } else {
                Text("Freed \(formatBytes(result.freedBytes)). \(result.failureCount) file\(result.failureCount == 1 ? "" : "s") couldn't be moved (in use or protected).")
            }
        }
    }

    // MARK: Hero

    private var hero: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(heroValue)
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("Duplicate files — reclaim redundant copies")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.isDupScanning {
                ProgressView()
                    .controlSize(.small)
                Button(role: .cancel) { model.stopDupScan() } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .controlSize(.large)
                .help("Stop scanning")
            } else {
                Button { model.scanDuplicates() } label: {
                    Label(model.hasDupRun ? "Rescan" : "Scan", systemImage: "magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.isDupCleaning)
                .help("Find byte-for-byte identical files")
            }
        }
    }

    private var heroValue: String {
        if model.dupTotalWastedBytes > 0 { return formatBytes(model.dupTotalWastedBytes) }
        if model.isDupScanning { return "Scanning…" }
        return model.hasDupRun ? "Nothing found" : "—"
    }

    // MARK: Filters

    private var filterRow: some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) {
                Text("Min size")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("", selection: $model.dupMinSize) {
                    Text("1 MB").tag(UInt64(1024 * 1024))
                    Text("10 MB").tag(UInt64(10 * 1024 * 1024))
                    Text("100 MB").tag(UInt64(100 * 1024 * 1024))
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            Spacer()
        }
        .disabled(model.isDupScanning)
    }

    // MARK: Idle / empty

    private var idlePrompt: some View {
        EmptyStateView(
            symbol: "doc.on.doc",
            tint: .purple,
            title: "Find duplicate files",
            message: "Vitals looks through Downloads, Documents, Desktop, Movies, Music and Pictures for files whose contents are byte-for-byte identical — the same photo saved twice, a re-downloaded installer, a copied export. It keeps one of each set and lets you move the rest to the Trash, recoverable from the Finder. Nothing is matched on name or size alone — every set is confirmed by a full content hash.",
            hints: [
                .init(symbol: "photo.on.rectangle", label: "Copied media"),
                .init(symbol: "arrow.down.circle", label: "Re-downloads"),
                .init(symbol: "checkmark.shield", label: "Content-verified"),
            ]
        ) {
            Button { model.scanDuplicates() } label: {
                Label("Scan", systemImage: "magnifyingglass")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private var emptyState: some View {
        EmptyStateView(
            symbol: "checkmark.seal.fill",
            tint: .green,
            title: "No duplicates found",
            message: "No byte-for-byte identical files at or above this size in your content folders. Lower the minimum size to widen the search."
        ) {
            Button { model.scanDuplicates() } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
            }
            .controlSize(.large)
        }
    }

    // MARK: Toolbar + list

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button("Select redundant copies") { model.selectRedundantDuplicates() }
                .controlSize(.small)
                .disabled(model.duplicateGroups.isEmpty)
            Button("Select none") { model.clearDupSelection() }
                .controlSize(.small)
                .disabled(model.dupSelection.isEmpty)
            Spacer()
        }
    }

    private var groupList: some View {
        LazyVStack(spacing: 10) {
            ForEach(model.duplicateGroups) { group in
                DuplicateGroupRow(
                    group: group,
                    redundantSelected: model.isGroupRedundantSelected(group),
                    selectedURLs: selectedURLs(in: group),
                    toggleGroup: { model.toggleDuplicateGroup(group) },
                    toggleFile: { model.toggleDuplicate($0) },
                    onQuickLook: { previewURL = $0 },
                    onReveal: { revealFileInFinder($0) }
                )
            }
        }
    }

    /// Which of a group's own copies are selected — scoped so a toggle in one set
    /// doesn't re-render every other set's row.
    private func selectedURLs(in group: DuplicateScanner.Group) -> Set<URL> {
        Set(group.files.map(\.url).filter(model.dupSelection.contains))
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Label("Moves to the Trash — recoverable from the Finder, nothing deleted outright.", systemImage: "trash")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if model.dupSelectedCount > 0 {
                Text("\(model.dupSelectedCount) file\(model.dupSelectedCount == 1 ? "" : "s") · \(formatBytes(model.dupSelectedBytes))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Button { confirming = true } label: {
                if model.isDupCleaning {
                    Label("Moving…", systemImage: "trash")
                } else {
                    Label(trashButtonTitle, systemImage: "trash")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.dupSelection.isEmpty || model.isDupCleaning)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var trashButtonTitle: String {
        model.dupSelectedBytes > 0 ? "Move to Trash \(formatBytes(model.dupSelectedBytes))…" : "Move to Trash…"
    }
}

// MARK: - Rows

private struct DuplicateGroupRow: View {
    let group: DuplicateScanner.Group
    let redundantSelected: Bool
    let selectedURLs: Set<URL>
    let toggleGroup: () -> Void
    let toggleFile: (URL) -> Void
    let onQuickLook: (URL) -> Void
    let onReveal: (URL) -> Void
    @State private var expanded = false

    var body: some View {
        VStack(spacing: 0) {
            header
            if expanded {
                ForEach(group.files) { file in
                    Divider()
                        .opacity(0.35)
                        .padding(.leading, 47)
                    DuplicateFileRow(
                        file: file,
                        isKeeper: file.url == group.keeper?.url,
                        selected: selectedURLs.contains(file.url),
                        toggle: { toggleFile(file.url) },
                        onQuickLook: { onQuickLook(file.url) },
                        onReveal: { onReveal(file.url) }
                    )
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(redundantSelected ? AnyShapeStyle(Color.accentColor.opacity(0.10)) : AnyShapeStyle(.quaternary.opacity(0.3)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    redundantSelected ? AnyShapeStyle(Color.accentColor.opacity(0.55)) : AnyShapeStyle(.separator.opacity(0.5)),
                    lineWidth: 1
                )
        )
        .animation(.easeOut(duration: 0.15), value: redundantSelected)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button { toggleGroup() } label: {
                HStack(spacing: 11) {
                    Image(nsImage: FileIconCache.shared.icon(forFileExtension: group.keeper?.url.pathExtension ?? ""))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 26, height: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.keeper?.name ?? "\(group.count) identical files")
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("\(group.count) copies · \(formatBytes(group.sizeBytes)) each")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text("reclaim \(formatBytes(group.wastedBytes)) by keeping one")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 10)
                    Text(formatBytes(group.wastedBytes))
                        .font(.system(.callout, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .frame(width: 74, alignment: .trailing)
                    Image(systemName: redundantSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16))
                        .foregroundStyle(redundantSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(expanded ? "Hide copies" : "Show \(group.count) copies")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

private struct DuplicateFileRow: View {
    let file: DuplicateScanner.File
    let isKeeper: Bool
    let selected: Bool
    let toggle: () -> Void
    let onQuickLook: () -> Void
    let onReveal: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(parentPath)
                            .font(.system(size: 12))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if isKeeper && !selected { keeperBadge }
                    }
                    Text(modifiedCaption)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 8)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary))
            }
            .padding(.leading, 47)
            .padding(.trailing, 14)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Rectangle().fill(hovered ? AnyShapeStyle(.quaternary.opacity(0.4)) : AnyShapeStyle(.clear)))
        .onHover { hovered = $0 }
        .contextMenu {
            Button("Quick Look", systemImage: "eye") { onQuickLook() }
            Button("Open", systemImage: "arrow.up.forward.app") { NSWorkspace.shared.open(file.url) }
            Button("Reveal in Finder", systemImage: "magnifyingglass") { onReveal() }
        }
    }

    private var keeperBadge: some View {
        Text("Keeps")
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(Color.green.opacity(0.16)))
            .foregroundStyle(.green)
            .help("The copy Vitals keeps by default — the oldest in the set")
    }

    private var parentPath: String {
        (file.url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
    }

    private var modifiedCaption: String {
        guard let date = file.modified else { return "modified date unknown" }
        return "modified \(date.formatted(.relative(presentation: .named)))"
    }
}
