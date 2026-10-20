import SwiftUI
import Charts

/// The Overview's one live chart, with a metric switcher. Only the selected
/// series renders.
struct PerformanceHistoryCard: View {
    @Environment(VitalsModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @State private var metric: Metric = .temp
    @Namespace private var indicator

    enum Metric: String, CaseIterable, Identifiable {
        case temp, cpu, gpu, memory, power, network
        var id: String { rawValue }
        var title: String {
            switch self {
            case .temp: return "Temp"
            case .cpu: return "CPU"
            case .gpu: return "GPU"
            case .memory: return "Memory"
            case .power: return "Power"
            case .network: return "Network"
            }
        }
        var symbol: String {
            switch self {
            case .temp: return "thermometer.medium"
            case .cpu: return "gauge.with.dots.needle.50percent"
            case .gpu: return "cpu.fill"
            case .memory: return "memorychip"
            case .power: return "bolt.fill"
            case .network: return "network"
            }
        }
    }

    /// GPU/Power/Network only when the chart has data for them. Derived from
    /// `chartHistory` alone, so a hidden window's frozen chart stays frozen instead
    /// of redrawing whenever a live reading changes.
    private var available: [Metric] {
        Metric.allCases.filter { metric in
            switch metric {
            case .gpu: return chartHistory.hasReading(\.gpuUsage)
            case .power: return chartHistory.hasReading(\.totalWatts)
            case .network: return chartHistory.hasReading(\.netInPerSec)
            default: return true
            }
        }
    }

    private var chartHistory: [VitalsModel.Sample] { model.chartHistory }

    var body: some View {
        let metrics = available
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Last \(settings.historyMinutes) minutes", systemImage: metric.symbol)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                switcher(metrics)
            }
            Deferred {
                chart
            }
            .frame(height: 190)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .cardBackground()
        // Keep the selection valid if a metric's reading disappears.
        .onChange(of: metrics) { _, list in
            if !list.contains(metric) { metric = .temp }
        }
    }

    // MARK: Switcher

    private func switcher(_ metrics: [Metric]) -> some View {
        HStack(spacing: 2) {
            ForEach(metrics) { item in
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
        let lines = series(for: metric)
        return MetricChart(
            samples: chartHistory,
            series: lines,
            yLabel: axisLabel,
            yDomain: yDomain(lines),
            legend: legend
        ) { tooltip($0) }
    }

    private func series(for metric: Metric) -> [ChartSeries<VitalsModel.Sample>] {
        switch metric {
        case .temp:
            return [
                .init(name: "Hottest core", color: .red.opacity(0.7)) { settings.display($0.hottestCPU) },
                .init(name: "CPU average", color: .orange, lineWidth: 2) { settings.display($0.averageCPU) },
            ]
        case .cpu:
            return [.init(name: "CPU", color: .blue, area: 0.35) { $0.usage }]
        case .gpu:
            return [.init(name: "GPU", color: .purple, area: 0.35) { $0.gpuUsage }]
        case .memory:
            return [
                .init(name: "Memory", color: .indigo) { gigabytes($0.memoryUsed) },
                .init(name: "Swap", color: .orange) { gigabytes($0.swapUsed) },
            ]
        case .power:
            return [.init(name: "Power", color: .yellow, area: 0.35) { $0.totalWatts }]
        case .network:
            return [
                .init(name: "Download", color: .mint) { $0.netInPerSec.map { $0 / 1_000_000 } },
                .init(name: "Upload", color: .orange) { $0.netOutPerSec.map { $0 / 1_000_000 } },
            ]
        }
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
            Text("Power \(sample.totalWatts.map(wattsText) ?? "—")")
        case .network:
            Text("↓ \(sample.netInPerSec.map(NetworkFormat.rate) ?? "—")")
            Text("↑ \(sample.netOutPerSec.map(NetworkFormat.rate) ?? "—")")
        }
    }

    // MARK: Per-metric scale / labels

    /// Legend order for the multi-series views; nil for the single-series ones,
    /// which colour their marks directly.
    private var legend: [String]? {
        switch metric {
        case .temp: return ["CPU average", "Hottest core"]
        case .memory: return ["Memory", "Swap"]
        case .network: return ["Download", "Upload"]
        case .cpu, .gpu, .power: return nil
        }
    }

    private var axisLabel: String {
        switch metric {
        case .temp: return settings.unit.symbol
        case .cpu, .gpu: return "%"
        case .memory: return "GB"
        case .power: return "W"
        case .network: return "MB/s"
        }
    }

    private func yDomain(_ series: [ChartSeries<VitalsModel.Sample>]) -> ClosedRange<Double> {
        switch metric {
        case .cpu, .gpu:
            return 0...100
        case .power:
            return 0...max((chartHistory.bounds(of: series)?.upperBound ?? 1) * 1.15, 1)
        case .network:
            // Peak of either direction, in MB/s; a 0.1 MB/s floor keeps an idle
            // link's chart from stretching noise across the full height.
            return 0...max((chartHistory.bounds(of: series)?.upperBound ?? 0) * 1.15, 0.1)
        case .memory:
            // The constant physical total, not `model.memory`, which changes every tick.
            return 0...max(gigabytes(model.memoryTotal), 1)
        case .temp:
            guard let bounds = chartHistory.bounds(of: series) else { return settings.display(30)...settings.display(90) }
            return (bounds.lowerBound - 5)...(bounds.upperBound + 5)
        }
    }
}
