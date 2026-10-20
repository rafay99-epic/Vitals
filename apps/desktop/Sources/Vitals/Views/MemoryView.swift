import SwiftUI

/// The Memory section: the `MemoryCard` hero, then usage over time, the full
/// composition, live VM page traffic, and the top memory consumers.
struct MemoryView: View {
    var body: some View {
        MetricScroll {
            MemoryCard()
            MemoryUsageHistoryCard()
            MemoryCompositionCard()
            MemoryActivityCard()
            TopMemoryProcessesCard()
        }
    }
}

struct MemoryCard: View {
    @Environment(VitalsModel.self) private var model

    private struct Segment: Identifiable {
        let label: String
        let bytes: UInt64
        let color: Color
        var id: String { label }
    }

    var body: some View {
        SectionCard(title: "Memory", symbol: "memorychip") {
            if let memory = model.memory {
                VStack(alignment: .leading, spacing: 12) {
                    header(memory)
                    breakdownBar(memory)
                    legend(memory)
                    Divider()
                    swapAndPressure(memory)
                }
            } else {
                CardPlaceholder("Memory statistics unavailable.")
            }
        }
    }

    private func header(_ memory: MemorySnapshot) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(String(format: "%.2f GB", gigabytes(memory.used)))
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .numericTransition()
            Text("used of \(String(format: "%.0f GB", gigabytes(memory.total)))")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            pressureBadge(memory.pressure)
        }
    }

    private func segments(_ memory: MemorySnapshot) -> [Segment] {
        [
            Segment(label: "App", bytes: memory.app, color: .blue),
            Segment(label: "Wired", bytes: memory.wired, color: .orange),
            Segment(label: "Compressed", bytes: memory.compressed, color: .purple),
            Segment(label: "Cached", bytes: memory.cached, color: .green.opacity(0.7))
        ]
    }

    private func breakdownBar(_ memory: MemorySnapshot) -> some View {
        GeometryReader { geometry in
            let total = max(Double(memory.total), 1)
            HStack(spacing: 1) {
                ForEach(segments(memory)) { segment in
                    segment.color
                        .frame(width: geometry.size.width * Double(segment.bytes) / total)
                }
                Color.secondary.opacity(0.15)  // free
            }
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .frame(height: 14)
    }

    private func legend(_ memory: MemorySnapshot) -> some View {
        let items = segments(memory) + [Segment(label: "Free", bytes: memory.free, color: .secondary.opacity(0.3))]
        // Fixed columns, never `.adaptive`: adaptive grids reflow mid-animation.
        let columns = Array(repeating: GridItem(.flexible(), alignment: .leading), count: items.count)
        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(items) { item in
                HStack(spacing: 6) {
                    LegendSwatch(color: item.color, label: item.label).foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.2f GB", gigabytes(item.bytes))).monospacedDigit()
                }
                .font(.caption)
            }
        }
    }

    private func swapAndPressure(_ memory: MemorySnapshot) -> some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Swap used").font(.caption).foregroundStyle(.secondary)
                Text(swapSummary(memory))
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .foregroundStyle(memory.swapUsed > 0 ? AnyShapeStyle(.orange) : AnyShapeStyle(.primary))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Memory pressure").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Circle().fill(pressureColor(memory.pressure)).frame(width: 9, height: 9)
                    Text(memory.pressure.label)
                        .font(.system(.body, design: .rounded, weight: .medium))
                }
            }
            Spacer()
        }
    }

    private func pressureBadge(_ pressure: MemoryPressure) -> some View {
        Text(pressure.label)
            .font(.caption.weight(.medium))
            .capsuleTag(pressureColor(pressure))
    }
}

// MARK: - Usage history

private struct MemoryUsageHistoryCard: View {
    @Environment(VitalsModel.self) private var model

    var body: some View {
        // One pass for swap presence and the Y ceiling, outside the per-sample
        // closure. Swap can exceed installed RAM, so the domain takes the larger of
        // the two, or a swap spike would clip.
        let maxSwapGB = model.chartHistory.reduce(0.0) { max($0, gigabytes($1.swapUsed)) }
        let hasSwap = maxSwapGB > 0
        let upperGB = max(gigabytes(model.memoryTotal), maxSwapGB, 1)
        var series: [ChartSeries<VitalsModel.Sample>] = [
            .init(name: "Used", color: .blue, area: 0.35) { gigabytes($0.memoryUsed) }
        ]
        if hasSwap {
            series.append(.init(name: "Swap", color: .orange) { gigabytes($0.swapUsed) })
        }
        return ChartCard(
            title: "Usage history",
            symbol: "chart.xyaxis.line",
            legend: series.map { LegendSwatch(color: $0.color, label: $0.name) }
        ) {
            MetricChart(samples: model.chartHistory, series: series, yLabel: "GB", yDomain: 0...upperGB)
        }
    }
}

// MARK: - Composition detail

/// The full breakdown the hero's legend summarises, with each region's share of
/// physical RAM spelled out, plus swap, which the bar doesn't cover.
private struct MemoryCompositionCard: View {
    @Environment(VitalsModel.self) private var model

    var body: some View {
        SectionCard(title: "Composition", symbol: "chart.pie.fill") {
            if let memory = model.memory {
                MetricRowGrid(rows: rows(memory))
            } else {
                CardPlaceholder("Memory statistics unavailable.")
            }
        }
    }

    private func rows(_ memory: MemorySnapshot) -> [MetricRow] {
        var rows = [
            row("app.dashed", "App memory", memory.app, of: memory.total),
            row("lock.fill", "Wired", memory.wired, of: memory.total),
            row("rectangle.compress.vertical", "Compressed", memory.compressed, of: memory.total),
            row("tray.full.fill", "Cached files", memory.cached, of: memory.total),
            row("circle.dashed", "Free", memory.free, of: memory.total)
        ]
        rows.append(MetricRow(symbol: "arrow.left.arrow.right", label: "Swap used", value: swapSummary(memory)))
        return rows
    }

    private func row(_ symbol: String, _ label: String, _ bytes: UInt64, of total: UInt64) -> MetricRow {
        let percent = total > 0 ? Double(bytes) / Double(total) * 100 : 0
        return MetricRow(symbol: symbol, label: label,
                         value: String(format: "%.2f GB · %.0f%%", gigabytes(bytes), percent))
    }
}

// MARK: - VM activity

/// Live VM page traffic. Usually 0/s on a healthy Mac; sustained page-outs or
/// swap-ins are the signal that RAM is tight.
private struct MemoryActivityCard: View {
    @Environment(VitalsModel.self) private var model

    var body: some View {
        SectionCard(title: "Activity", symbol: "waveform.path.ecg") {
            if let activity = model.memoryActivity {
                VStack(alignment: .leading, spacing: 12) {
                    MetricRowGrid(rows: rows(activity))
                    Text("Virtual-memory traffic · 1 page = \(Self.pageKB) KB")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            } else {
                // No memory reading (VM/restricted Mac) is permanently unavailable; a real
                // Mac shows "Gathering…" only until the first rate (two readings) lands.
                CardPlaceholder(model.memory == nil ? "Memory activity unavailable." : "Gathering…")
            }
        }
    }

    private static let pageKB = Int(vm_kernel_page_size / 1024)

    private func rows(_ activity: MemoryActivity) -> [MetricRow] {
        [
            row("arrow.down.circle", "Page-ins", activity.pageInsPerSec),
            row("arrow.up.circle", "Page-outs", activity.pageOutsPerSec),
            row("arrow.down.to.line", "Swap-ins", activity.swapInsPerSec),
            row("arrow.up.to.line", "Swap-outs", activity.swapOutsPerSec),
            row("arrow.down.right.and.arrow.up.left", "Compressions", activity.compressionsPerSec),
            row("arrow.up.left.and.arrow.down.right", "Decompressions", activity.decompressionsPerSec)
        ]
    }

    private func row(_ symbol: String, _ label: String, _ rate: Double) -> MetricRow {
        MetricRow(symbol: symbol, label: label, value: String(format: "%.0f/s", rate))
    }
}

// MARK: - Top memory consumers

private struct TopMemoryProcessesCard: View {
    @Environment(VitalsModel.self) private var model

    var body: some View {
        SectionCard(title: "Top memory", symbol: "list.bullet") {
            if model.topMemoryProcesses.isEmpty {
                CardPlaceholder("Gathering…", minHeight: 120)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.topMemoryProcesses) { process in
                        HStack {
                            Text(process.name)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Text(formatBytes(process.memory))
                                .font(.system(.callout, design: .rounded, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .font(.callout)
                    }
                    Text("Physical-memory footprint per process")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}
