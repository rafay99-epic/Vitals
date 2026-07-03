import SwiftUI
import AppKit
import QuickLook

/// The two newer Cleanup pages: per-project Developer junk (regenerable build
/// artifacts, deleted permanently) and a Large-&-Old Files review (personal
/// files, only ever moved to the recoverable Trash). Both are display-only —
/// every filesystem call goes through `CleanupModel`.

// MARK: - Developer page

struct CleanupDeveloperPage: View {
    @ObservedObject var model: CleanupModel
    @State private var confirming = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    hero
                    if !model.hasDevRun {
                        idlePrompt
                    } else if !model.isDevScanning && model.devProjects.isEmpty {
                        emptyState
                    } else {
                        toolbar
                        projectList
                    }
                }
                .padding(20)
            }
            Divider()
                .opacity(0.5)
            footer
        }
        .confirmationDialog(
            "Delete \(formatBytes(model.devSelectedBytes))?",
            isPresented: $confirming,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { model.cleanDev() }
        } message: {
            Text(confirmMessage)
        }
        .alert(
            "Cleanup finished",
            isPresented: Binding(get: { model.lastDevResult != nil }, set: { if !$0 { model.dismissDevResult() } }),
            presenting: model.lastDevResult
        ) { _ in
            Button("OK") { model.dismissDevResult() }
        } message: { result in
            if result.failureCount == 0 {
                Text("Freed \(formatBytes(result.freedBytes)).")
            } else {
                Text("Freed \(formatBytes(result.freedBytes)). \(result.failureCount) item\(result.failureCount == 1 ? "" : "s") couldn't be removed.")
            }
        }
    }

    private var confirmMessage: String {
        let names = model.selectedDevProjects
            .map { "\($0.name) (\(formatBytes(model.selectedBytes(in: $0))))" }
            .joined(separator: ", ")
        return "\(names). These are permanently deleted — npm install, cargo build, or pod install regenerates them."
    }

    // MARK: Hero

    private var hero: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(heroValue)
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("Build artifacts and dependencies — all regenerable")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.isDevScanning {
                ProgressView()
                    .controlSize(.small)
                Button(role: .cancel) { model.stopDevScan() } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .controlSize(.large)
                .help("Stop scanning")
            } else {
                Button { model.scanDev() } label: {
                    Label(model.hasDevRun ? "Rescan" : "Scan", systemImage: "magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.isDevCleaning)
                .help("Find regenerable build artifacts")
            }
        }
    }

    private var heroValue: String {
        if model.devTotalBytes > 0 { return formatBytes(model.devTotalBytes) }
        if model.isDevScanning { return "Scanning…" }
        guard model.hasDevRun else { return "—" }
        // Projects found but every artifact measured to 0 bytes: show the honest
        // total, not "Nothing found" (which is only for an empty result).
        return model.devProjects.isEmpty ? "Nothing found" : formatBytes(model.devTotalBytes)
    }

    // MARK: Idle / empty

    private var idlePrompt: some View {
        EmptyStateView(
            symbol: "hammer",
            tint: .orange,
            title: "Reclaim build junk",
            message: "Vitals finds regenerable developer artifacts in your code folders — node_modules, target, .next, Pods, DerivedData and friends — grouped by project. None of it is source: an npm install, cargo build, or pod install rebuilds them. Scan to see what each project is holding.",
            hints: [
                .init(symbol: "shippingbox", label: "Dependencies"),
                .init(symbol: "hammer", label: "Build output"),
                .init(symbol: "clock", label: "Stale projects"),
            ]
        ) {
            Button { model.scanDev() } label: {
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
            title: "Nothing found",
            message: "No developer artifacts in your usual code folders — your projects are already lean, or your code lives somewhere Vitals doesn't scan."
        ) {
            Button { model.scanDev() } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
            }
            .controlSize(.large)
        }
    }

    // MARK: Toolbar + list

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button("Select stale (7+ days)") { model.selectStaleDev(olderThanDays: 7) }
                .controlSize(.small)
                .disabled(model.isDevScanning)
            Button("Select none") { model.clearDevSelection() }
                .controlSize(.small)
                .disabled(model.devSelection.isEmpty)
            Spacer()
        }
    }

    private var projectList: some View {
        LazyVStack(spacing: 10) {
            ForEach(model.devProjects) { project in
                DevProjectRow(
                    project: project,
                    selected: model.isDevProjectSelected(project),
                    isScanning: model.isDevScanning,
                    selectedArtifacts: selectedArtifactURLs(in: project),
                    toggleProject: { model.toggleDevProject(project) },
                    toggleArtifact: { model.toggleDevArtifact($0) }
                )
            }
        }
    }

    /// Which of a project's own artifacts are selected — scoped so a toggle in
    /// one project doesn't change (and re-render) every other project's row.
    private func selectedArtifactURLs(in project: DevJunkScanner.Project) -> Set<URL> {
        Set(project.artifacts.map(\.url).filter(model.devSelection.contains))
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Label("Permanently removed — a build or install regenerates them.", systemImage: "hammer")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if model.devSelectedCount > 0 {
                Text("\(model.devSelectedCount) item\(model.devSelectedCount == 1 ? "" : "s") · \(formatBytes(model.devSelectedBytes)) selected")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Button { confirming = true } label: {
                if model.isDevCleaning {
                    Label("Cleaning…", systemImage: "hammer")
                } else {
                    Label(cleanButtonTitle, systemImage: "trash")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.devSelection.isEmpty || model.isDevCleaning || model.devSelectedBytes == 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var cleanButtonTitle: String {
        model.devSelectedBytes > 0 ? "Clean \(formatBytes(model.devSelectedBytes))…" : "Clean…"
    }
}

// MARK: Developer rows

private struct DevProjectRow: View {
    let project: DevJunkScanner.Project
    let selected: Bool
    let isScanning: Bool
    let selectedArtifacts: Set<URL>
    let toggleProject: () -> Void
    let toggleArtifact: (URL) -> Void
    @State private var expanded = false

    var body: some View {
        VStack(spacing: 0) {
            header
            if expanded {
                ForEach(project.artifacts) { artifact in
                    Divider()
                        .opacity(0.35)
                        .padding(.leading, 47)
                    DevArtifactRow(
                        artifact: artifact,
                        selected: selectedArtifacts.contains(artifact.url),
                        isScanning: isScanning,
                        toggle: { toggleArtifact(artifact.url) }
                    )
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(selected ? AnyShapeStyle(Color.accentColor.opacity(0.10)) : AnyShapeStyle(.quaternary.opacity(0.3)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    selected ? AnyShapeStyle(Color.accentColor.opacity(0.55)) : AnyShapeStyle(.separator.opacity(0.5)),
                    lineWidth: 1
                )
        )
        .animation(.easeOut(duration: 0.15), value: selected)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button { toggleProject() } label: {
                HStack(spacing: 11) {
                    Image(systemName: "folder.badge.gearshape")
                        .font(.system(size: 13, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.orange)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.orange.opacity(0.14))
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(project.name)
                            .font(.system(size: 13, weight: .semibold))
                        Text(abbreviatedPath)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(activeCaption)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 10)
                    sizeLabel
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16))
                        .foregroundStyle(selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary))
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
            .help(expanded ? "Hide artifacts" : "Show \(project.artifacts.count) artifact\(project.artifacts.count == 1 ? "" : "s")")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var sizeLabel: some View {
        if isScanning && project.totalBytes == 0 {
            ProgressView()
                .controlSize(.small)
                .frame(width: 74, alignment: .trailing)
        } else {
            Text(formatBytes(project.totalBytes))
                .font(.system(.callout, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .frame(width: 74, alignment: .trailing)
        }
    }

    private var abbreviatedPath: String {
        (project.root.path as NSString).abbreviatingWithTildeInPath
    }

    private var activeCaption: String {
        guard let date = project.lastActive else { return "activity unknown" }
        return "active \(date.formatted(.relative(presentation: .named)))"
    }
}

private struct DevArtifactRow: View {
    let artifact: DevJunkScanner.Artifact
    let selected: Bool
    let isScanning: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 10) {
                Text(artifact.kindName)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.quaternary.opacity(0.5)))
                Spacer(minLength: 8)
                if isScanning && artifact.sizeBytes == 0 {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(formatBytes(artifact.sizeBytes))
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(.secondary)
                }
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
    }
}

// MARK: - Files page

struct CleanupFilesPage: View {
    @ObservedObject var model: CleanupModel
    @State private var confirming = false
    @State private var previewURL: URL?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    hero
                    filterRow
                    if !model.hasFilesRun {
                        idlePrompt
                    } else if !model.isFilesScanning && model.largeFiles.isEmpty {
                        emptyState
                    } else {
                        toolbar
                        fileList
                    }
                }
                .padding(20)
            }
            // In-app preview — a context-menu action sets `previewURL`.
            .quickLookPreview($previewURL)
            Divider()
                .opacity(0.5)
            footer
        }
        .onChange(of: model.filesMinSize) { _, _ in if model.hasFilesRun { model.scanFiles() } }
        .onChange(of: model.filesMinAgeDays) { _, _ in if model.hasFilesRun { model.scanFiles() } }
        .confirmationDialog(
            "Move \(formatBytes(model.filesSelectedBytes)) to the Trash?",
            isPresented: $confirming,
            titleVisibility: .visible
        ) {
            Button("Move to Trash") { model.trashFiles() }
        } message: {
            Text("\(model.filesSelectedCount) file\(model.filesSelectedCount == 1 ? "" : "s") will be moved to the Trash. You can recover them from the Finder until you empty it.")
        }
        .alert(
            "Moved to Trash",
            isPresented: Binding(get: { model.lastFilesResult != nil }, set: { if !$0 { model.dismissFilesResult() } }),
            presenting: model.lastFilesResult
        ) { _ in
            Button("OK") { model.dismissFilesResult() }
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
                Text("Large & old files — review and move to Trash")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.isFilesScanning {
                ProgressView()
                    .controlSize(.small)
                Button(role: .cancel) { model.stopFilesScan() } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .controlSize(.large)
                .help("Stop scanning")
            } else {
                Button { model.scanFiles() } label: {
                    Label(model.hasFilesRun ? "Rescan" : "Scan", systemImage: "magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.isFilesCleaning)
                .help("Review big and old files")
            }
        }
    }

    private var heroValue: String {
        if model.filesTotalBytes > 0 { return formatBytes(model.filesTotalBytes) }
        if model.isFilesScanning { return "Scanning…" }
        return model.hasFilesRun ? "Nothing found" : "—"
    }

    // MARK: Filters

    private var filterRow: some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) {
                Text("Size")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("", selection: $model.filesMinSize) {
                    Text("100 MB").tag(UInt64(100 * 1024 * 1024))
                    Text("500 MB").tag(UInt64(500 * 1024 * 1024))
                    Text("1 GB").tag(UInt64(1024 * 1024 * 1024))
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            HStack(spacing: 6) {
                Text("Age")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("", selection: $model.filesMinAgeDays) {
                    Text("Any").tag(Int?.none)
                    Text("90+ days").tag(Int?.some(90))
                    Text("180+ days").tag(Int?.some(180))
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            Spacer()
        }
        .disabled(model.isFilesScanning)
    }

    // MARK: Idle / empty

    private var idlePrompt: some View {
        EmptyStateView(
            symbol: "doc.text.magnifyingglass",
            tint: .blue,
            title: "Find large & old files",
            message: "Vitals reviews big files in Downloads, Documents, Desktop, Movies, Music and Pictures — the same idea as Storage in System Settings. Nothing is deleted: you pick what to move to the Trash, and it stays recoverable from the Finder. Set the size and age filters, then Scan.",
            hints: [
                .init(symbol: "arrow.down.circle", label: "Downloads"),
                .init(symbol: "film", label: "Media"),
                .init(symbol: "clock", label: "Old files"),
            ]
        ) {
            Button { model.scanFiles() } label: {
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
            title: "Nothing found",
            message: "No files match your size and age filters in your content folders. Lower the size or clear the age filter to widen the search."
        ) {
            Button { model.scanFiles() } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
            }
            .controlSize(.large)
        }
    }

    // MARK: Toolbar + list

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button("Select suggested") { model.selectSuggested() }
                .controlSize(.small)
                .disabled(!model.largeFiles.contains(where: \.isSuggested))
            Button("Select none") { model.clearFilesSelection() }
                .controlSize(.small)
                .disabled(model.filesSelection.isEmpty)
            Spacer()
        }
    }

    private var fileList: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(model.largeFiles.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Divider()
                        .opacity(0.35)
                        .padding(.leading, 45)
                }
                FileRow(
                    item: item,
                    selected: model.filesSelection.contains(item.url),
                    toggle: { model.toggleFile(item.url) },
                    onQuickLook: { previewURL = item.url },
                    onReveal: { revealFileInFinder(item.url) }
                )
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Label("Moves to the Trash — recoverable from the Finder, nothing deleted outright.", systemImage: "trash")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if model.filesSelectedCount > 0 {
                Text("\(model.filesSelectedCount) file\(model.filesSelectedCount == 1 ? "" : "s") · \(formatBytes(model.filesSelectedBytes))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Button { confirming = true } label: {
                if model.isFilesCleaning {
                    Label("Moving…", systemImage: "trash")
                } else {
                    Label(trashButtonTitle, systemImage: "trash")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.filesSelection.isEmpty || model.isFilesCleaning)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var trashButtonTitle: String {
        model.filesSelectedBytes > 0 ? "Move to Trash \(formatBytes(model.filesSelectedBytes))…" : "Move to Trash…"
    }
}

private struct FileRow: View {
    let item: LargeFileScanner.Item
    let selected: Bool
    let toggle: () -> Void
    let onQuickLook: () -> Void
    let onReveal: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 11) {
                Image(nsImage: FileIconCache.shared.icon(forFileExtension: item.url.pathExtension))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 22, height: 22)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(item.name)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if item.isSuggested { suggestedBadge }
                    }
                    Text(parentPath)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(modifiedCaption)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 12)

                Text(formatBytes(item.sizeBytes))
                    .font(.system(.callout, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(.secondary)
                    .frame(width: 82, alignment: .trailing)

                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Rectangle().fill(hovered ? AnyShapeStyle(.quaternary.opacity(0.4)) : AnyShapeStyle(.clear)))
        .onHover { hovered = $0 }
        .contextMenu {
            Button("Quick Look", systemImage: "eye") { onQuickLook() }
            Button("Open", systemImage: "arrow.up.forward.app") { NSWorkspace.shared.open(item.url) }
            Button("Reveal in Finder", systemImage: "magnifyingglass") { onReveal() }
        }
    }

    private var suggestedBadge: some View {
        Text("Suggested")
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(Color.accentColor.opacity(0.16)))
            .foregroundStyle(Color.accentColor)
            .help("Vitals flags this as obvious junk — an old installer or a dead partial download")
    }

    private var parentPath: String {
        (item.url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
    }

    private var modifiedCaption: String {
        guard let date = item.modified else { return "modified date unknown" }
        return "modified \(date.formatted(.relative(presentation: .named)))"
    }
}

@MainActor private func revealFileInFinder(_ url: URL) {
    NSWorkspace.shared.activateFileViewerSelecting([url])
}
