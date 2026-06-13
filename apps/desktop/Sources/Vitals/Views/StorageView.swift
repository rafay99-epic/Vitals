import SwiftUI
import AppKit

/// The Storage tab: occupied space at a glance (a capacity bar over category
/// cards) and an analyzer table that drills into the largest folders and files
/// under any location. This surface only *reads* — it never deletes or moves
/// anything; reclaiming space lives in Cleanup, where it gets confirmation and
/// reversibility. "Reveal in Finder" is the most it will ever do to a file.
struct StorageView: View {
    @ObservedObject var model: StorageModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    capacityHero
                    categoryGrid
                    analyzerCard
                }
                .padding(20)
            }
            Divider()
                .opacity(0.5)
            footer
        }
        .onAppear { if model.categories.isEmpty { model.refresh() } }
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
                if model.isScanning {
                    ProgressView()
                        .controlSize(.small)
                }
                Button {
                    model.refresh()
                } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
                .controlSize(.large)
                .disabled(model.isScanning)
                .help("Measure storage again")
            }

            if let volume = model.volume {
                CapacityBar(
                    total: volume.total,
                    used: volume.used,
                    segments: model.categories.map { ($0.kind.tint, $0.sizeBytes) }
                )
                legend
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
                Text("Other")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
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
            }

            analyzerTable
        }
        .padding(16)
        .cardBackground()
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

    @ViewBuilder
    private var analyzerTable: some View {
        if model.entries.isEmpty {
            Text(model.isAnalyzing ? "Measuring…" : "Empty")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, minHeight: 120)
        } else {
            let shown = Array(model.entries.prefix(200))
            LazyVStack(spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 {
                        Divider()
                            .opacity(0.35)
                            .padding(.leading, 40)
                    }
                    StorageRow(
                        entry: entry,
                        fraction: model.largestEntryBytes > 0 ? Double(entry.sizeBytes) / Double(model.largestEntryBytes) : 0,
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
            if model.entries.count > shown.count {
                Text("Showing the 200 largest of \(model.entries.count) items")
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

                if category.sizeBytes == 0 && isScanning {
                    ProgressView()
                        .controlSize(.small)
                } else if category.sizeBytes == 0 {
                    Text("Empty")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                } else {
                    Text(formatBytes(category.sizeBytes))
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
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
