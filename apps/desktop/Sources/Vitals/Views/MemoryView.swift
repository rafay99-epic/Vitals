import SwiftUI
import Charts

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
        return SectionCard(title: "Usage history", symbol: "chart.xyaxis.line") {
            VStack(alignment: .leading, spacing: 10) {
                Deferred { chart(hasSwap: hasSwap, upperGB: upperGB) }.frame(height: 150)
                legend(hasSwap: hasSwap)
            }
        }
    }

    private func chart(hasSwap: Bool, upperGB: Double) -> some View {
        Chart(model.chartHistory) { sample in
            AreaMark(x: .value("Time", sample.time),
                     y: .value("Used", gigabytes(sample.memoryUsed)))
                .foregroundStyle(LinearGradient(colors: [.blue.opacity(0.35), .blue.opacity(0.02)],
                                                startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.catmullRom)
            LineMark(x: .value("Time", sample.time),
                     y: .value("Used", gigabytes(sample.memoryUsed)))
                .foregroundStyle(.blue)
                .interpolationMethod(.catmullRom)
            if hasSwap {
                LineMark(x: .value("Time", sample.time),
                         y: .value("Swap", gigabytes(sample.swapUsed)),
                         series: .value("Series", "Swap"))
                    .foregroundStyle(.orange)
                    .interpolationMethod(.catmullRom)
            }
        }
        .chartYScale(domain: 0...upperGB)
        .chartYAxisLabel("GB")
    }

    private func legend(hasSwap: Bool) -> some View {
        HStack(spacing: 16) {
            swatch(.blue, "Used")
            if hasSwap { swatch(.orange, "Swap") }
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func swatch(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 9, height: 9)
            Text(label)
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
                Text("Memory statistics unavailable.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
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
                Text(model.memory == nil ? "Memory activity unavailable." : "Gathering…")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
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
                Text("Gathering…")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
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
