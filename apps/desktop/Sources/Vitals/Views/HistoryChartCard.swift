import SwiftUI

// MARK: - Chart

struct HistoryChartCard: View {
    @Environment(AppSettings.self) private var settings
    let samples: [HistorySample]
    let metric: HistoryView.Metric
    let range: HistoryRange

    var body: some View {
        ChartCard(title: rangeTitle, symbol: "chart.xyaxis.line", height: 240) {
            chart
        }
    }

    private var rangeTitle: String {
        switch range {
        case .hour: return "Last hour"
        case .day:  return "Last 24 hours"
        case .week: return "Last 7 days"
        case .all:  return "All history"
        }
    }

    private var chart: some View {
        let lines = series
        return MetricChart(samples: samples, series: lines, yLabel: yLabel, yDomain: yDomain(lines), legend: legend)
    }

    private var series: [ChartSeries<HistorySample>] {
        switch metric {
        case .temp:
            return [
                .init(name: "Hottest", color: .red.opacity(0.7)) { settings.display($0.hottestTemp) },
                .init(name: "Average", color: .orange) { settings.display($0.avgTemp) }
            ]
        case .cpu:
            return [.init(name: "CPU", color: .blue, area: 0.32) { $0.cpuUsage }]
        case .gpu:
            return [.init(name: "GPU", color: .purple, area: 0.32) { $0.gpuUsage }]
        case .memory:
            return [.init(name: "Memory", color: .indigo) { $0.memoryGB }]
        case .network:
            return [
                .init(name: "Download", color: .mint) { $0.netInBps.map { $0 / 1_000_000 } },
                .init(name: "Upload", color: .orange) { $0.netOutBps.map { $0 / 1_000_000 } }
            ]
        case .disk:
            return [
                .init(name: "Read", color: .yellow) { $0.diskReadBps.map { $0 / 1_000_000 } },
                .init(name: "Write", color: .orange) { $0.diskWriteBps.map { $0 / 1_000_000 } }
            ]
        case .battery:
            return [.init(name: "Battery", color: .green, area: 0.32) { $0.batteryPercent }]
        case .power:
            return [.init(name: "Power", color: .orange) { $0.socWatts }]
        }
    }

    /// Legend order for the current metric (nil for the single-series views,
    /// which colour their marks directly).
    private var legend: [String]? {
        switch metric {
        case .temp: return ["Average", "Hottest"]
        case .network: return ["Download", "Upload"]
        case .disk: return ["Read", "Write"]
        case .cpu, .gpu, .memory, .battery, .power: return nil
        }
    }

    private var yLabel: String {
        switch metric {
        case .temp: return settings.unit.symbol
        case .cpu, .gpu, .battery: return "%"
        case .memory: return "GB"
        case .network, .disk: return "MB/s"
        case .power: return "W"
        }
    }

    private func yDomain(_ series: [ChartSeries<HistorySample>]) -> ClosedRange<Double> {
        switch metric {
        case .cpu, .gpu, .battery: return 0...100
        case .power, .memory:
            return 0...max((samples.bounds(of: series)?.upperBound ?? 1) * 1.1, 1)
        case .network, .disk:
            // Peak of either direction in MB/s; the small floor keeps an idle
            // link's noise from stretching across the full chart height.
            return 0...max((samples.bounds(of: series)?.upperBound ?? 0) * 1.1, 0.1)
        case .temp:
            guard let bounds = samples.bounds(of: series) else { return settings.display(30)...settings.display(90) }
            return (bounds.lowerBound - 5)...(bounds.upperBound + 5)
        }
    }
}
