import SwiftUI
import Charts

/// One "over time" chart for the whole dashboard, with a Temp/CPU/GPU/Memory
/// segmented switcher. Replaces the four separate history cards — only the
/// selected series renders, so the dashboard keeps a single live chart.
struct PerformanceHistoryCard: View {
    @EnvironmentObject private var model: VitalsModel
    @EnvironmentObject private var settings: AppSettings
    /// True only while the Dashboard is visible. When false, `chartHistory`
    /// resolves to empty so the `Chart` builds no marks and — crucially —
    /// doesn't read `model.chartHistory`/`model.memory`, so it stops
    /// re-rendering on every sample tick while another tab is up. The `Chart`
    /// view itself stays mounted (no 50–150 ms re-layout on return); only its
    /// data goes empty.
    let isActive: Bool
    @State private var metric: Metric = .temp
    @State private var hoverTime: Date?
    @Namespace private var indicator

    enum Metric: String, CaseIterable, Identifiable {
        case temp, cpu, gpu, memory, power
        var id: String { rawValue }
        var title: String {
            switch self {
            case .temp: return "Temp"
            case .cpu: return "CPU"
            case .gpu: return "GPU"
            case .memory: return "Memory"
            case .power: return "Power"
            }
        }
        var symbol: String {
            switch self {
            case .temp: return "thermometer.medium"
            case .cpu: return "gauge.with.dots.needle.50percent"
            case .gpu: return "cpu.fill"
            case .memory: return "memorychip"
            case .power: return "bolt.fill"
            }
        }
    }

    /// GPU/Power only when this Mac exposes a reading for them.
    private var available: [Metric] {
        Metric.allCases.filter { metric in
            switch metric {
            case .gpu: return model.gpu != nil
            case .power: return model.power != nil
            default: return true
            }
        }
    }

    /// The downsampled series the chart draws — emptied when this tab isn't
    /// visible so the marks, the y-domain, and the hover lookup all collapse to
    /// nothing and the chart stops subscribing to per-tick model updates. The
    /// ternary short-circuits, so `model.chartHistory` is never read while
    /// inactive (no observation → no re-render).
    private var chartHistory: [VitalsModel.Sample] {
        isActive ? model.chartHistory : []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Last \(settings.historyMinutes) minutes", systemImage: metric.symbol)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                switcher
            }
            Deferred {
                chart
            }
            .frame(height: 190)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .cardBackground()
        // Keep the selection valid if the GPU segment disappears.
        .onChange(of: available) { _, list in
            if !list.contains(metric) { metric = .temp }
        }
    }

    // MARK: Segmented switcher (matches the header tab capsule)

    private var switcher: some View {
        HStack(spacing: 2) {
            ForEach(available) { item in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) { metric = item }
                } label: {
                    Text(item.title)
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(metric == item ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .background {
                    if metric == item {
                        Capsule().fill(.quaternary).matchedGeometryEffect(id: "seg", in: indicator)
                    }
                }
            }
        }
        .padding(3)
        .background(Capsule().fill(.quaternary.opacity(0.45)))
    }

    // MARK: Chart

    private var chart: some View {
        Chart {
            marks
            if let sample = chartHistory.nearest(to: hoverTime) {
                RuleMark(x: .value("Time", sample.time))
                    .foregroundStyle(.secondary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        HoverTooltip(time: sample.time) { tooltip(sample) }
                    }
            }
        }
        // Scope the legend/colors to the selected metric's series only — a global
        // scale would list every series (Memory/Swap) even on the Temp view.
        .chartForegroundStyleScale(domain: seriesStyle.domain, range: seriesStyle.range)
        .chartYScale(domain: yDomain)
        .chartYAxisLabel(axisLabel)
        .chartLegend(multiSeries ? .visible : .hidden)
        .chartHover($hoverTime)
    }

    @ChartContentBuilder
    private var marks: some ChartContent {
        switch metric {
        case .temp:
            ForEach(chartHistory) { sample in
                LineMark(x: .value("Time", sample.time),
                         y: .value("Temp", settings.display(sample.hottestCPU)),
                         series: .value("Series", "Hottest core"))
                    .foregroundStyle(by: .value("Series", "Hottest core"))
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("Time", sample.time),
                         y: .value("Temp", settings.display(sample.averageCPU)),
                         series: .value("Series", "CPU average"))
                    .foregroundStyle(by: .value("Series", "CPU average"))
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2))
            }
        case .cpu:
            ForEach(chartHistory) { sample in
                areaLine(sample.time, sample.usage, .blue)
            }
        case .gpu:
            ForEach(chartHistory) { sample in
                if let usage = sample.gpuUsage {
                    areaLine(sample.time, usage, .purple)
                }
            }
        case .memory:
            ForEach(chartHistory) { sample in
                LineMark(x: .value("Time", sample.time),
                         y: .value("GB", gigabytes(sample.memoryUsed)),
                         series: .value("Series", "Memory"))
                    .foregroundStyle(by: .value("Series", "Memory"))
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("Time", sample.time),
                         y: .value("GB", gigabytes(sample.swapUsed)),
                         series: .value("Series", "Swap"))
                    .foregroundStyle(by: .value("Series", "Swap"))
                    .interpolationMethod(.catmullRom)
            }
        case .power:
            ForEach(chartHistory) { sample in
                if let watts = sample.totalWatts {
                    areaLine(sample.time, watts, .yellow)
                }
            }
        }
    }

    @ChartContentBuilder
    private func areaLine(_ time: Date, _ value: Double, _ color: Color) -> some ChartContent {
        AreaMark(x: .value("Time", time), y: .value("%", value))
            .foregroundStyle(LinearGradient(colors: [color.opacity(0.35), color.opacity(0.02)],
                                            startPoint: .top, endPoint: .bottom))
            .interpolationMethod(.catmullRom)
        LineMark(x: .value("Time", time), y: .value("%", value))
            .foregroundStyle(color)
            .interpolationMethod(.catmullRom)
    }

    @ViewBuilder
    private func tooltip(_ sample: VitalsModel.Sample) -> some View {
        switch metric {
        case .temp:
            Text("Avg \(settings.format(sample.averageCPU))")
            Text("Hottest \(settings.format(sample.hottestCPU))")
        case .cpu:
            Text(String(format: "CPU %.0f%%", sample.usage))
        case .gpu:
            Text(String(format: "GPU %.0f%%", sample.gpuUsage ?? 0))
        case .memory:
            Text(String(format: "Memory %.2f GB", gigabytes(sample.memoryUsed)))
            Text(String(format: "Swap %.2f GB", gigabytes(sample.swapUsed)))
        case .power:
            Text("Power \(wattsText(sample.totalWatts ?? 0))")
        }
    }

    // MARK: Per-metric scale / labels

    private var multiSeries: Bool { metric == .temp || metric == .memory }

    /// Legend/color domain for the *current* metric only (empty for the
    /// single-series CPU/GPU views, which colour their marks directly).
    private var seriesStyle: (domain: [String], range: [Color]) {
        switch metric {
        case .temp: return (["CPU average", "Hottest core"], [.orange, .red.opacity(0.7)])
        case .memory: return (["Memory", "Swap"], [.indigo, .orange])
        case .cpu, .gpu, .power: return ([], [])
        }
    }

    private var axisLabel: String {
        switch metric {
        case .temp: return settings.unit.symbol
        case .cpu, .gpu: return "%"
        case .memory: return "GB"
        case .power: return "W"
        }
    }

    private var yDomain: ClosedRange<Double> {
        switch metric {
        case .cpu, .gpu:
            return 0...100
        case .power:
            let watts = chartHistory.compactMap { $0.totalWatts }
            return 0...max((watts.max() ?? 1) * 1.15, 1)
        case .memory:
            // Only read `model.memory` while active — otherwise the chart would
            // re-render every tick (memory publishes each sample) for nothing.
            let total = isActive ? (model.memory?.total ?? 1) : 1
            return 0...max(gigabytes(total), 1)
        case .temp:
            let temps = chartHistory.flatMap { [$0.averageCPU, $0.hottestCPU] }.map(settings.display)
            guard let lo = temps.min(), let hi = temps.max() else { return settings.display(30)...settings.display(90) }
            return (lo - 5)...(hi + 5)
        }
    }
}
