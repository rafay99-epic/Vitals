import SwiftUI

/// The Cleanup tab: regenerable data as selectable cards, cleaned on explicit
/// confirmation. A Quick/Deep switch chooses the reach — Quick stays in the
/// user domain (no password); Deep adds age-gated system categories that need
/// one administrator prompt. Scanning is manual; nothing runs until asked.
struct CleanupView: View {
    @ObservedObject var model: CleanupModel
    /// True only while Cleanup is the visible tab; the view stays mounted.
    var isActive: Bool
    @EnvironmentObject private var settings: AppSettings
    /// Persisted so the chosen depth sticks across launches.
    @AppStorage("cleanupDepth") private var depth: CleanDepth = .quick
    @State private var confirming = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    hero
                    if !model.hasRun {
                        idlePrompt
                    } else if !model.isScanning && model.totalBytes == 0 {
                        allClean
                    } else {
                        grid
                    }
                }
                .padding(20)
            }
            Divider()
                .opacity(0.5)
            footer
        }
        .onChange(of: isActive, initial: true) { _, active in
            if active && settings.autoScanCleanup && !model.hasRun {
                model.scan(depth: depth)
            }
        }
        .onChange(of: depth) { _, newDepth in
            // Switching depth re-measures for the new set of categories.
            if model.hasRun { model.scan(depth: newDepth) }
        }
        .confirmationDialog(
            "Clean \(formatBytes(model.selectedBytes))?",
            isPresented: $confirming,
            titleVisibility: .visible
        ) {
            Button(model.selectionNeedsAdmin ? "Deep Clean" : "Clean", role: .destructive) { model.clean() }
        } message: {
            Text(confirmationMessage)
        }
        .alert(
            "Cleanup finished",
            isPresented: Binding(get: { model.lastResult != nil }, set: { if !$0 { model.dismissResult() } }),
            presenting: model.lastResult
        ) { _ in
            Button("OK") { model.dismissResult() }
        } message: { result in
            if result.failures.isEmpty {
                Text("Freed \(formatBytes(result.freedBytes)) (\(result.removedItems) items)\(result.usedAdmin ? " — protected items included." : ".")")
            } else {
                Text("Freed \(formatBytes(result.freedBytes)). \(result.failures.count) items couldn't be removed (in use or protected).")
            }
        }
        .alert(
            "Couldn't finish deep clean",
            isPresented: Binding(get: { model.lastError != nil }, set: { if !$0 { model.dismissError() } }),
            presenting: model.lastError
        ) { _ in
            Button("OK") { model.dismissError() }
        } message: { message in
            Text(message)
        }
    }

    private var confirmationMessage: String {
        var lines = "Selected caches and logs are deleted — apps rebuild them automatically."
        if model.selected.contains(.trash) {
            lines += " Emptying the Trash is permanent."
        }
        if model.selectionNeedsAdmin {
            lines += " System files need your administrator password; only files older than the retention window are removed."
        }
        return lines
    }

    // MARK: Hero

    private var hero: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(heroValue)
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .contentTransition(.numericText())
                Text(heroSubtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("", selection: $depth) {
                ForEach(CleanDepth.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .disabled(model.isCleaning)
            .help("Quick cleans user caches; Deep adds system files (needs admin)")
            if model.isScanning {
                ProgressView()
                    .controlSize(.small)
                Button(role: .cancel) {
                    model.cancelScan()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .controlSize(.large)
                .help("Stop scanning")
            } else {
                Button {
                    model.scan(depth: depth)
                } label: {
                    Label(model.hasRun ? "Rescan" : "Scan", systemImage: "magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.isCleaning)
                .help("Measure what's reclaimable")
            }
        }
    }

    private var heroValue: String {
        if model.totalBytes > 0 { return formatBytes(model.totalBytes) }
        if model.isScanning { return "Scanning…" }
        return model.hasRun ? "All clean" : "—"
    }

    private var heroSubtitle: String {
        if model.isScanning { return "measuring \(depth == .deep ? "user and system" : "user") junk" }
        let populated = model.categories.filter { $0.sizeBytes > 0 }.count
        if model.totalBytes > 0 {
            return "reclaimable across \(populated) categories — all of it regenerable"
        }
        return model.hasRun ? "nothing worth reclaiming right now" : "scan to see what's reclaimable"
    }

    // MARK: Idle prompt

    private var idlePrompt: some View {
        EmptyStateView(
            symbol: "sparkles",
            tint: .orange,
            title: "Free up space safely",
            message: "Vitals only finds regenerable junk — caches, logs, the Trash. Quick stays in your home folder; Deep also clears age-gated system files with one admin prompt. Auto-scan is in Settings.",
            hints: [
                .init(symbol: "shippingbox", label: "Caches"),
                .init(symbol: "doc.text", label: "Logs"),
                .init(symbol: "lock", label: "System · Deep"),
            ]
        ) {
            Button { model.scan(depth: depth) } label: {
                Label("Scan", systemImage: "magnifyingglass")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private var allClean: some View {
        EmptyStateView(
            symbol: "checkmark.seal.fill",
            tint: .green,
            title: "All clean",
            message: "Nothing worth reclaiming right now — your caches, logs, and Trash are already tidy."
        ) {
            Button { model.scan(depth: depth) } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
            }
            .controlSize(.large)
        }
    }

    // MARK: Category grid

    private var grid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
            ForEach(model.categories) { category in
                CategoryCard(
                    category: category,
                    isScanning: model.isScanning,
                    isSelected: model.selected.contains(category.kind)
                ) {
                    if model.selected.contains(category.kind) {
                        model.selected.remove(category.kind)
                    } else {
                        model.selected.insert(category.kind)
                    }
                }
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Label(
                model.selectionNeedsAdmin
                    ? "System files removed with your permission — only old, regenerable data."
                    : "Only regenerable data — documents and settings are never touched.",
                systemImage: model.selectionNeedsAdmin ? "lock.shield" : "checkmark.shield"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            Spacer()
            if !model.selected.isEmpty {
                Text("\(model.selected.count) selected")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Button {
                confirming = true
            } label: {
                if model.isCleaning {
                    Label("Cleaning…", systemImage: "sparkles")
                } else {
                    Label(cleanButtonTitle, systemImage: model.selectionNeedsAdmin ? "lock.fill" : "sparkles")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.selected.isEmpty || model.isCleaning || model.selectedBytes == 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var cleanButtonTitle: String {
        if model.selectedBytes == 0 { return "Clean" }
        let size = formatBytes(model.selectedBytes)
        return model.selectionNeedsAdmin ? "Deep Clean \(size)…" : "Clean \(size)"
    }
}

// MARK: - Category card

private extension CleanupCategory.Kind {
    var tint: Color {
        switch self {
        case .xcode: return .blue
        case .devCaches: return .orange
        case .homebrew: return .yellow
        case .appCaches: return .purple
        case .logs: return .teal
        case .trash: return .red
        case .recentItems: return .indigo
        case .systemCaches: return .gray
        case .systemLogs: return .mint
        case .crashReports: return .red
        case .systemTemp: return .brown
        case .gpuCaches: return .pink
        }
    }
}

private struct CategoryCard: View {
    let category: CleanupCategory
    let isScanning: Bool
    let isSelected: Bool
    let toggle: () -> Void

    /// Disabled only once a scan has settled with nothing to remove.
    private var hasNothing: Bool { !isScanning && category.sizeBytes == 0 }

    private var emptyLabel: String {
        if category.kind.requiresAdmin { return "Nothing old enough" }
        return category.items.isEmpty ? "Nothing found" : "Empty"
    }

    var body: some View {
        Button(action: toggle) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 9) {
                    Image(systemName: category.kind.symbol)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(category.kind.tint)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(category.kind.tint.opacity(0.14))
                        )
                    Text(category.kind.title)
                        .font(.system(size: 13, weight: .semibold))
                    if category.kind.requiresAdmin {
                        Image(systemName: "lock")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .help("Removing these needs administrator rights")
                    }
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16))
                        .foregroundStyle(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary))
                }

                Text(category.kind.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2, reservesSpace: true)

                HStack(alignment: .firstTextBaseline) {
                    if isScanning && category.sizeBytes == 0 {
                        ProgressView()
                            .controlSize(.small)
                    } else if category.sizeBytes == 0 {
                        Text(emptyLabel)
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                    } else {
                        Text(formatBytes(category.sizeBytes))
                            .font(.system(.title3, design: .rounded, weight: .semibold))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                    Spacer()
                    if category.sizeBytes > 0 {
                        Text("\(category.items.count) item\(category.items.count == 1 ? "" : "s")")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.10)) : AnyShapeStyle(.quaternary.opacity(0.35)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.55)) : AnyShapeStyle(.separator.opacity(0.5)),
                        lineWidth: 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(hasNothing)
        .opacity(hasNothing ? 0.55 : 1)
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }
}
