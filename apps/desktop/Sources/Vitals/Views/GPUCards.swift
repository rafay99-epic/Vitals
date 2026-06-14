import SwiftUI
import Charts

/// Current GPU state: utilization hero, memory used/total, temperature, name.
struct GPUCard: View {
    @EnvironmentObject private var model: VitalsModel
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        SectionCard(title: "GPU", symbol: "cpu.fill") {
            if let gpu = model.gpu {
                VStack(alignment: .leading, spacing: 12) {
                    header(gpu)
                    if gpu.memoryUsed != nil {
                        memoryBar(gpu)
                        memoryLegend(gpu)
                    }
                    Divider()
                    details(gpu)
                }
            } else {
                Text("GPU statistics unavailable.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            }
        }
    }

    private func header(_ gpu: GPUSnapshot) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(gpu.utilization.map { String(format: "%.0f%%", $0) } ?? "—")
                .font(.system(size: 32, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text("utilization")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            if let name = gpu.name {
                Text(name)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func memoryBar(_ gpu: GPUSnapshot) -> some View {
        GeometryReader { geometry in
            let fraction = gpu.memoryFraction ?? 0
            HStack(spacing: 1) {
                Color.purple
                    .frame(width: geometry.size.width * fraction)
                Color.secondary.opacity(0.15)  // free
            }
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .frame(height: 14)
    }

    private func memoryLegend(_ gpu: GPUSnapshot) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(Color.purple).frame(width: 9, height: 9)
            Text("Memory in use").foregroundStyle(.secondary)
            Spacer()
            Text(memoryText(gpu)).monospacedDigit()
        }
        .font(.caption)
    }

    private func memoryText(_ gpu: GPUSnapshot) -> String {
        guard let used = gpu.memoryUsed else { return "—" }
        if let total = gpu.memoryTotal, total > 0 {
            return String(format: "%.2f GB of %.0f GB", gigabytes(used), gigabytes(total))
        }
        return String(format: "%.2f GB", gigabytes(used))
    }

    private func details(_ gpu: GPUSnapshot) -> some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Temperature").font(.caption).foregroundStyle(.secondary)
                Text(model.gpuTemp.map { settings.formatWithUnit($0, decimals: 0) } ?? "—")
                    .font(.system(.body, design: .rounded, weight: .medium))
            }
            Spacer()
        }
    }
}

/// GPU utilization over time — mirrors `CPUUsageCard`.
struct GPUHistoryCard: View {
    @EnvironmentObject private var model: VitalsModel
    @EnvironmentObject private var settings: AppSettings
    @State private var hoverTime: Date?

    var body: some View {
        SectionCard(title: "GPU usage · last \(settings.historyMinutes) minutes", symbol: "chart.line.uptrend.xyaxis") {
            Deferred {
                Chart {
                    ForEach(model.chartHistory) { sample in
                        if let usage = sample.gpuUsage {
                            AreaMark(
                                x: .value("Time", sample.time),
                                y: .value("%", usage)
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.purple.opacity(0.35), .purple.opacity(0.02)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .interpolationMethod(.catmullRom)

                            LineMark(
                                x: .value("Time", sample.time),
                                y: .value("%", usage)
                            )
                            .foregroundStyle(.purple)
                            .interpolationMethod(.catmullRom)
                        }
                    }

                    if let sample = model.history.nearest(to: hoverTime), let usage = sample.gpuUsage {
                        RuleMark(x: .value("Time", sample.time))
                            .foregroundStyle(.secondary.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1))
                            .annotation(
                                position: .top,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                            ) {
                                HoverTooltip(time: sample.time) {
                                    Text(String(format: "GPU %.0f%%", usage))
                                }
                            }
                    }
                }
                .chartYScale(domain: 0...100)
                .chartYAxisLabel("%")
                .chartHover($hoverTime)
            }
            .frame(height: 150)
        }
    }
}
