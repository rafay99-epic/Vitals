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
            .init(name: "Used", color: .blue, area: 0.35) { gigabytes($0.memoryUsed) },
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
            row("circle.dashed", "Free", memory.free, of: memory.total),
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
            row("arrow.up.left.and.arrow.down.right", "Decompressions", activity.decompressionsPerSec),
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
