import SwiftUI

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
        PageHero(value: heroValue, subtitle: "Build artifacts and dependencies — all regenerable") {
            ScanButtons(
                isScanning: model.isDevScanning,
                hasRun: model.hasDevRun,
                disabled: model.isDevCleaning,
                help: "Find regenerable build artifacts",
                scan: { model.scanDev() },
                stop: { model.stopDevScan() }
            )
        }
        .monospacedDigit()
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
