import SwiftUI
import AppKit

/// Cleanup's Developer page: per-project regenerable build artifacts, deleted
/// permanently. Display-only; every filesystem call goes through `CleanupModel`.

// MARK: - Developer page

struct CleanupDeveloperPage: View {
    @Bindable var model: CleanupModel
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
        // Projects found but every artifact measured 0 bytes: show the total.
        // "Nothing found" is only for an empty result.
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

    /// Which of a project's own artifacts are selected, scoped so a toggle in
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
