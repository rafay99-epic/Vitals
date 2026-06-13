import SwiftUI
import AppKit
import Charts

/// The Storage tab: occupied space at a glance (a capacity bar over category
/// cards) and an analyzer table that drills into the largest folders and files
/// under any location. This surface only *reads* — it never deletes or moves
/// anything; reclaiming space lives in Cleanup, where it gets confirmation and
/// reversibility. "Reveal in Finder" is the most it will ever do to a file.
/// Which overview graphic the hero shows. Both visualize the same volume
/// composition, so the user picks one rather than seeing both at once.
enum OverviewChart: String, CaseIterable, Identifiable {
    case bar, donut
    var id: String { rawValue }
    var symbol: String { self == .bar ? "chart.bar.xaxis" : "chart.pie.fill" }
}

struct StorageView: View {
    @ObservedObject var model: StorageModel
    @EnvironmentObject private var settings: AppSettings
    @State private var confirmWholeDisk = false
    /// Persisted so the chosen graphic sticks across launches.
    @AppStorage("storageOverviewChart") private var overviewChart: OverviewChart = .bar

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    capacityHero
                    if !model.hasFullDiskAccess {
                        fdaBanner
                    }
                    if model.hasRun {
                        categoryGrid
                        insightsCard
                        analyzerCard
                    } else {
                        idlePrompt
                    }
                }
                .padding(20)
            }
            Divider()
                .opacity(0.5)
            footer
        }
        .onAppear {
            // Capacity and the access check are instant; the disk-walking
            // analysis waits for the button unless auto-analyze is on.
            model.loadVolume()
            model.refreshAccess()
            if settings.autoAnalyzeStorage && !model.hasRun {
                model.analyze(includeHidden: settings.analyzerIncludesHidden)
            }
        }
    }

    private func runAnalyze() {
        model.analyze(includeHidden: settings.analyzerIncludesHidden)
    }

    private func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Full Disk Access banner

    private var fdaBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.shield")
                .font(.system(size: 20, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.orange)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text("Grant Full Disk Access for a complete report")
                    .font(.system(size: 13, weight: .semibold))
                Text("Without it, Vitals measures what it can and skips the folders macOS protects, so some totals read low. Add Vitals in System Settings, then Recheck.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            VStack(spacing: 6) {
                Button("Open Settings") { openFullDiskAccessSettings() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Button("Recheck") { model.refreshAccess() }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.orange.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.orange.opacity(0.35), lineWidth: 1)
        )
    }

    // MARK: Insights

    @ViewBuilder
    private var insightsCard: some View {
        if !model.insights.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Label("Hidden space", systemImage: "eye.trianglebadge.exclamationmark")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if model.isScanningInsights {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                Text("Places that quietly fill up. Vitals points them out — it never deletes them; reclaim space in Cleanup.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LazyVStack(spacing: 0) {
                    ForEach(Array(model.insights.enumerated()), id: \.element.id) { index, insight in
                        if index > 0 {
                            Divider()
                                .opacity(0.35)
                                .padding(.leading, 40)
                        }
                        InsightRow(
                            insight: insight,
                            onOpen: { model.openInsight(insight) },
                            onReveal: { revealInFinder(insight.url) }
                        )
                    }
                }
            }
            .padding(16)
            .cardBackground()
        }
    }

    // MARK: Capacity hero

    private var capacityHero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(heroValue)
                        .font(.system(size: 32, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(heroSubtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if model.volume != nil {
                    Picker("", selection: $overviewChart) {
                        ForEach(OverviewChart.allCases) { style in
                            Image(systemName: style.symbol).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .help("Switch between the bar and the donut")
                }
                if model.isBusy {
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
                        runAnalyze()
                    } label: {
                        Label(model.hasRun ? "Re-analyze" : "Analyze", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .help("Measure where your storage is used")
                }
            }

            if let volume = model.volume {
                // One graphic at a time — the bar and the donut show the same
                // composition, so showing both was redundant and cramped.
                VStack(spacing: 10) {
                    switch overviewChart {
                    case .bar:
                        CapacityBar(
                            total: volume.total,
                            used: volume.used,
                            segments: model.categories.map { ($0.kind.tint, $0.sizeBytes ?? 0) }
                        )
                    case .donut:
                        // Charts pay 50–150 ms on first layout, so mount the
                        // donut through Deferred — opens against a placeholder.
                        Deferred {
                            CompositionDonut(volume: volume, categories: model.categories)
                        }
                        .frame(width: 132, height: 132)
                    }
                    legend
                }
                .animation(.easeInOut(duration: 0.2), value: overviewChart)
            }
        }
        .padding(16)
        .cardBackground()
    }

    private var heroValue: String {
        guard let volume = model.volume else { return "—" }
        return "\(formatBytes(volume.used)) used"
    }

    private var heroSubtitle: String {
        guard let volume = model.volume else { return "reading volume capacity…" }
        return "\(formatBytes(volume.free)) available of \(formatBytes(volume.total))"
    }

    private var legend: some View {
        HStack(spacing: 14) {
            ForEach(model.categories) { category in
                HStack(spacing: 5) {
                    Circle()
                        .fill(category.kind.tint)
                        .frame(width: 7, height: 7)
                    Text(category.kind.title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 5) {
                Circle().fill(Color.secondary.opacity(0.45)).frame(width: 7, height: 7)
                // Before a breakdown exists we only know used vs free, so the
                // whole used portion is honestly just "Used".
                Text(model.categories.isEmpty ? "Used" : "Other")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    // MARK: Idle prompt

    private var idlePrompt: some View {
        EmptyStateView(
            symbol: "internaldrive",
            tint: .blue,
            title: "Find what's using your space",
            message: "Vitals measures your folders on demand — nothing crawls the disk in the background. Analyze to see the breakdown and drill into the biggest items. Stop any time; auto-analyze is in Settings.",
            hints: [
                .init(symbol: "square.grid.2x2", label: "By category"),
                .init(symbol: "list.bullet", label: "Largest folders"),
                .init(symbol: "eye.trianglebadge.exclamationmark", label: "Hidden space"),
            ]
        ) {
            Button { runAnalyze() } label: {
                Label("Analyze Storage", systemImage: "magnifyingglass")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    // MARK: Category grid

    private var categoryGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
            ForEach(model.categories) { category in
                StorageCategoryCard(
                    category: category,
                    isScanning: model.isScanning,
                    isCurrent: model.path.first == category.root
                ) {
                    model.openCategory(category)
                }
            }
        }
    }

    // MARK: Analyzer

    private var analyzerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button {
                    model.goUp()
                } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.borderless)
                .disabled(model.path.count <= 1)
                .help("Up one level")

                breadcrumb

                Spacer()
                if model.isAnalyzing {
                    ProgressView()
                        .controlSize(.small)
                }
                if settings.allowWholeDiskScan {
                    Button {
                        confirmWholeDisk = true
                    } label: {
                        Label("Whole disk", systemImage: "externaldrive")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .disabled(model.isBusy)
                    .help("Scan the entire boot volume from the top")
                }
            }

            analyzerChart
            analyzerTable
        }
        .padding(16)
        .cardBackground()
        .confirmationDialog(
            "Scan the whole disk?",
            isPresented: $confirmWholeDisk,
            titleVisibility: .visible
        ) {
            Button("Scan Whole Disk") { model.analyzeWholeDisk() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This walks every readable folder from the top of your drive, including system areas, so it can take several minutes and use the disk heavily. Vitals only reads — nothing is deleted — and you can press Stop at any time.")
        }
    }

    private var breadcrumb: some View {
        HStack(spacing: 4) {
            ForEach(Array(model.path.enumerated()), id: \.offset) { index, url in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                Button {
                    model.jump(to: index)
                } label: {
                    Text(displayName(url))
                        .font(.system(size: 12, weight: index == model.path.count - 1 ? .semibold : .regular))
                        .foregroundStyle(index == model.path.count - 1 ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .disabled(index == model.path.count - 1)
            }
        }
    }

    /// A horizontal bar chart of the current folder's largest items — a quick
    /// visual comparison above the full, drillable table.
    @ViewBuilder
    private var analyzerChart: some View {
        let top = Array(model.entries.prefix(8))
        if top.contains(where: { $0.sizeBytes > 0 }) {
            Deferred {
                TopItemsChart(entries: top)
            }
            .frame(height: CGFloat(top.count) * 26 + 12)
        }
    }

    @ViewBuilder
    private var analyzerTable: some View {
        if model.entries.isEmpty {
            VStack(spacing: 8) {
                if model.isAnalyzing {
                    ProgressView().controlSize(.small)
                    Text("Measuring…").font(.callout).foregroundStyle(.secondary)
                } else {
                    Image(systemName: "folder")
                        .font(.system(size: 22))
                        .foregroundStyle(.tertiary)
                    Text("This folder is empty").font(.callout).foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 120)
        } else {
            // entries is already the largest-first top-N from the model.
            let largest = model.largestEntryBytes
            LazyVStack(spacing: 0) {
                ForEach(Array(model.entries.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 {
                        Divider()
                            .opacity(0.35)
                            .padding(.leading, 40)
                    }
                    StorageRow(
                        entry: entry,
                        fraction: largest > 0 ? Double(entry.sizeBytes) / Double(largest) : 0,
                        onOpen: {
                            if entry.isDirectory {
                                model.drill(into: entry)
                            } else {
                                revealInFinder(entry.url)
                            }
                        },
                        onReveal: { revealInFinder(entry.url) }
                    )
                }
            }
            if model.entryTotal > model.entries.count {
                Text("Showing the \(model.entries.count) largest of \(model.entryTotal) items")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Label("Storage only reads your disk — nothing here deletes. Reclaim space in Cleanup.", systemImage: "eye")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func displayName(_ url: URL) -> String {
        if url.path == FileManager.default.homeDirectoryForCurrentUser.path { return "Home" }
        if url.path == "/" { return "Macintosh HD" }
        return url.lastPathComponent
    }
}

@MainActor private func revealInFinder(_ url: URL) {
    NSWorkspace.shared.activateFileViewerSelecting([url])
}

// MARK: - Capacity bar

/// A horizontal capacity bar in the style of System Settings → Storage: the
/// used space is split into the measured categories, the remainder of used
/// space shows as a neutral "Other" segment, and free space is the empty track
/// behind it. Every width is a real proportion of the volume — nothing here is
/// padded to look fuller.
private struct CapacityBar: View {
    let total: UInt64
    let used: UInt64
    let segments: [(color: Color, bytes: UInt64)]

    /// Each visible slice as (color, fraction-of-total), in draw order.
    private var slices: [(color: Color, fraction: Double)] {
        func fraction(_ bytes: UInt64) -> Double { total > 0 ? Double(bytes) / Double(total) : 0 }
        let known = segments.reduce(UInt64(0)) { $0 + $1.bytes }
        let other = used > known ? used - known : 0
        var result = segments.map { (color: $0.color, fraction: fraction($0.bytes)) }
        if other > 0 {
            result.append((color: Color.secondary.opacity(0.45), fraction: fraction(other)))
        }
        return result
    }

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(Array(slices.enumerated()), id: \.offset) { _, slice in
                    Rectangle()
                        .fill(slice.color)
                        .frame(width: max(0, CGFloat(slice.fraction) * geo.size.width))
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: 16)
        .background(Capsule().fill(.quaternary.opacity(0.4)))
        .clipShape(Capsule())
        .animation(.easeOut(duration: 0.25), value: used)
    }
}

// MARK: - Category card

private extension StorageCategory.Kind {
    var tint: Color {
        switch self {
        case .userFiles: return .blue
        case .userLibrary: return .purple
        case .applications: return .green
        case .systemLibrary: return .orange
        }
    }
}

private struct StorageCategoryCard: View {
    let category: StorageCategory
    let isScanning: Bool
    let isCurrent: Bool
    let open: () -> Void

    var body: some View {
        Button(action: open) {
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
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }

                Text(category.kind.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2, reservesSpace: true)

                if let size = category.sizeBytes {
                    if size == 0 {
                        Text("Empty")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                    } else {
                        Text(formatBytes(size))
                            .font(.system(.title3, design: .rounded, weight: .semibold))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                } else if isScanning {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    // Stopped before this card was measured — say so honestly
                    // rather than implying it holds nothing.
                    Text("Not measured")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isCurrent ? AnyShapeStyle(Color.accentColor.opacity(0.10)) : AnyShapeStyle(.quaternary.opacity(0.35)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isCurrent ? AnyShapeStyle(Color.accentColor.opacity(0.55)) : AnyShapeStyle(.separator.opacity(0.5)),
                        lineWidth: 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: isCurrent)
    }
}

// MARK: - Analyzer row

private struct StorageRow: View {
    let entry: StorageEntry
    let fraction: Double
    let onOpen: () -> Void
    let onReveal: () -> Void

    @State private var hovered = false

    private var tint: Color { entry.isDirectory ? .accentColor : .secondary }

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 11) {
                Image(systemName: entry.isDirectory ? "folder.fill" : "doc")
                    .font(.system(size: 14))
                    .foregroundStyle(entry.isDirectory ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    RatioBar(fraction: fraction, tint: tint)
                }

                Spacer(minLength: 12)

                Text(entry.sizeBytes > 0 ? formatBytes(entry.sizeBytes) : "—")
                    .font(.system(.callout, design: .rounded, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 86, alignment: .trailing)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .opacity(entry.isDirectory ? 1 : 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Rectangle().fill(hovered ? AnyShapeStyle(.quaternary.opacity(0.4)) : AnyShapeStyle(.clear)))
        .onHover { hovered = $0 }
        .contextMenu {
            Button("Reveal in Finder", systemImage: "magnifyingglass") { onReveal() }
        }
        .help(entry.isDirectory ? "Open \(entry.name)" : "Reveal \(entry.name) in Finder")
    }
}

// MARK: - Insight row

private struct InsightRow: View {
    let insight: StorageAnalyzer.StorageInsight
    let onOpen: () -> Void
    let onReveal: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 11) {
                Image(systemName: "folder.badge.questionmark")
                    .font(.system(size: 14))
                    .foregroundStyle(.teal)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 1) {
                    Text(insight.name)
                        .font(.system(size: 13, weight: .medium))
                    Text(insight.detail)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 12)

                if let size = insight.sizeBytes {
                    Text(size > 0 ? formatBytes(size) : "Empty")
                        .font(.system(.callout, design: .rounded, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(size > 0 ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
                        .frame(width: 86, alignment: .trailing)
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 86, alignment: .trailing)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Rectangle().fill(hovered ? AnyShapeStyle(.quaternary.opacity(0.4)) : AnyShapeStyle(.clear)))
        .onHover { hovered = $0 }
        .contextMenu {
            Button("Reveal in Finder", systemImage: "magnifyingglass") { onReveal() }
        }
        .help("Open \(insight.name)")
    }
}

/// A thin proportional bar: how big this entry is relative to the largest one
/// in the current folder.
private struct RatioBar: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(.quaternary.opacity(0.5))
            GeometryReader { geo in
                Capsule()
                    .fill(tint.opacity(0.7))
                    .frame(width: max(0, min(1, fraction)) * geo.size.width)
            }
        }
        .frame(height: 4)
    }
}

// MARK: - Charts

/// A donut of how the whole volume divides: each measured category, the rest
/// of used space as "Other", and free space. Every wedge is a real proportion
/// — the center shows the honest used percentage.
private struct CompositionDonut: View {
    let volume: StorageAnalyzer.VolumeUsage
    let categories: [StorageCategory]

    private struct Slice: Identifiable {
        let label: String
        let bytes: UInt64
        let color: Color
        var id: String { label }
    }

    private var slices: [Slice] {
        var result: [Slice] = []
        var known: UInt64 = 0
        for category in categories {
            if let size = category.sizeBytes, size > 0 {
                result.append(.init(label: category.kind.title, bytes: size, color: category.kind.tint))
                known += size
            }
        }
        let other = volume.used > known ? volume.used - known : 0
        if other > 0 {
            result.append(.init(label: "Other", bytes: other, color: Color.secondary.opacity(0.5)))
        }
        if volume.free > 0 {
            result.append(.init(label: "Free", bytes: volume.free, color: Color.secondary.opacity(0.18)))
        }
        return result
    }

    var body: some View {
        Chart(slices) { slice in
            SectorMark(
                angle: .value("Size", Double(slice.bytes)),
                innerRadius: .ratio(0.62),
                angularInset: 1.5
            )
            .foregroundStyle(slice.color)
            .cornerRadius(2)
        }
        .chartLegend(.hidden)
        .overlay {
            VStack(spacing: 0) {
                Text("\(Int((volume.usedFraction * 100).rounded()))%")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("used")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Horizontal bars for a folder's largest items, ordered largest-first.
/// Folders take the accent color, files the secondary, so the two read apart.
private struct TopItemsChart: View {
    let entries: [StorageEntry]

    var body: some View {
        Chart(entries) { entry in
            BarMark(
                x: .value("Size", Double(entry.sizeBytes)),
                y: .value("Item", entry.name)
            )
            .foregroundStyle(entry.isDirectory ? Color.accentColor : Color.secondary)
            .cornerRadius(3)
        }
        // Keep the table's largest-first order (Charts would otherwise sort the
        // category axis alphabetically); first domain entry sits at the top, so
        // pass them largest-first to put the biggest bar on top.
        .chartYScale(domain: entries.map(\.name))
        .chartXAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let bytes = value.as(Double.self) {
                        Text(formatBytes(UInt64(max(0, bytes))))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisValueLabel {
                    if let name = value.as(String.self) {
                        Text(name)
                            .font(.caption2)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
        }
    }
}
