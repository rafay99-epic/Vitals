import SwiftUI
import Charts

/// The Memory segment: a deep-dive that used to be a single Dashboard-style card.
/// It leads with the shared `MemoryCard` hero (so the breakdown can never drift
/// from the Dashboard's), then adds the detail a monitor should show — usage over
/// time, the full composition with percentages, live VM page traffic, and the
/// heaviest memory consumers. Every number is a real reading: an idle rate shows
/// 0/s, an absent figure shows "—", nothing is smoothed or invented.
struct MemoryView: View {
    /// True only while Memory is the visible segment. Gates the history chart so
    /// it never rebuilds marks in the background (same rule as GPU/Battery).
    let isActive: Bool

    var body: some View {
        MetricScroll {
            MemoryCard()
            // Only mounted while active, so the chart isn't rebuilt every tick in
            // the background. Memory always reads, so no "contains" guard needed.
            if isActive {
                MemoryUsageHistoryCard()
            }
            MemoryCompositionCard()
            MemoryActivityCard()
            TopMemoryProcessesCard()
        }
    }
}

// MARK: - Usage history

private struct MemoryUsageHistoryCard: View {
    @EnvironmentObject private var model: VitalsModel

    var body: some View {
        // One pass over the series, hoisted out of the per-sample chart closure:
        // whether to draw the swap line at all, and the Y-axis ceiling. Swap can
        // exceed installed RAM, so the domain takes the larger of RAM and the
        // tallest swap reading — otherwise a swap spike would clip.
        let maxSwapGB = model.chartHistory.reduce(0.0) { max($0, gigabytes($1.swapUsed)) }
        let hasSwap = maxSwapGB > 0
        let upperGB = max(gigabytes(model.memoryTotal), maxSwapGB, 1)
        return SectionCard(title: "Usage history", symbol: "chart.xyaxis.line") {
            VStack(alignment: .leading, spacing: 10) {
                // Deferred keeps the 50–150 ms first-layout cost off the
                // tab-switch animation (see GPUView/BatteryView).
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
/// physical RAM spelled out — plus swap, which the bar doesn't cover.
private struct MemoryCompositionCard: View {
    @EnvironmentObject private var model: VitalsModel

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
        rows.append(MetricRow(symbol: "arrow.left.arrow.right", label: "Swap used", value: swapValue(memory)))
        return rows
    }

    private func row(_ symbol: String, _ label: String, _ bytes: UInt64, of total: UInt64) -> MetricRow {
        let percent = total > 0 ? Double(bytes) / Double(total) * 100 : 0
        return MetricRow(symbol: symbol, label: label,
                         value: String(format: "%.2f GB · %.0f%%", gigabytes(bytes), percent))
    }

    private func swapValue(_ memory: MemorySnapshot) -> String {
        guard memory.swapTotal > 0 else { return "None" }
        return String(format: "%.2f GB of %.1f GB", gigabytes(memory.swapUsed), gigabytes(memory.swapTotal))
    }
}

// MARK: - VM activity

/// Live virtual-memory page traffic. These are honestly 0/s on a healthy,
/// unpressured Mac — that's the point: sustained page-outs or swap-ins are the
/// signal that RAM is tight, so showing the real (often zero) rate matters.
private struct MemoryActivityCard: View {
    @EnvironmentObject private var model: VitalsModel

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
                // No memory reading at all (a VM/restricted Mac) is a permanent
                // "unavailable", matching the hero and Composition cards; a real
                // Mac only sits at "Gathering…" for the one tick before the first
                // rate (a rate needs two readings) lands.
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
    @EnvironmentObject private var model: VitalsModel

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
