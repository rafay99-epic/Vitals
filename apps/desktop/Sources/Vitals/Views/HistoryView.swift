import SwiftUI
import AppKit

/// The History section: a timeline of logged readings over the last hour, day,
/// week, or everything. Queries the SQLite store off-main, only while mounted.
struct HistoryView: View {
    @Environment(AppSettings.self) private var settings
    @Bindable var model: HistoryModel

    typealias Metric = HistoryMetric

    private struct ReloadKey: Equatable { let range: HistoryRange; let logging: Bool }

    var body: some View {
        MetricScroll {
            timeline
            // Fired alerts are independent of the metric log, so they show even
            // when logging is off and the chart is empty.
            if !model.alertEvents.isEmpty {
                AlertHistoryCard(events: model.alertEvents)
            }
            HistoryExportCard()
        }
        .task(id: ReloadKey(range: model.range, logging: settings.loggingEnabled)) {
            await model.reload()
        }
    }

    @ViewBuilder
    private var timeline: some View {
        if !model.samples.isEmpty {
            // Existing history stays browsable after logging is turned off; flag that
            // it won't keep growing.
            if !settings.loggingEnabled { loggingPausedNote }
            HistoryControls(range: $model.range, metric: $model.metric)
            HistoryChartCard(samples: model.samples, metric: model.metric, range: model.range)
            HistoryStatsCard(samples: model.samples, metric: model.metric)
        } else if model.loading {
            emptyState
        } else if !settings.loggingEnabled {
            loggingOffState
        } else {
            emptyState
        }
    }

    private var loggingPausedNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "pause.circle").foregroundStyle(.secondary)
            Text("Logging is off — showing what was recorded earlier.")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Resume") { settings.loggingEnabled = true }.controlSize(.small)
        }
        .padding(12)
        .cardBackground()
    }

    private var loggingOffState: some View {
        EmptyStateView(
            symbol: "chart.xyaxis.line",
            tint: .indigo,
            title: "History logging is off",
            message: "Turn on logging to record temperatures, usage, fans, and more, one reading every 10 seconds, stored locally in \((DataHome.directory.path as NSString).abbreviatingWithTildeInPath). Then browse and export the timeline here."
        ) {
            Button("Turn On Logging") { settings.loggingEnabled = true }
                .buttonStyle(.borderedProminent)
        }
    }

    private var emptyState: some View {
        EmptyStateView(
            symbol: model.loading ? "hourglass" : "clock.arrow.circlepath",
            tint: .indigo,
            title: model.loading ? "Reading history…" : "No history yet",
            message: model.loading
                ? "Loading the logged readings."
                : "Logging is on, but nothing's been recorded for this range yet. Check back in a few minutes."
        )
    }
}

// MARK: - Controls

private struct HistoryControls: View {
    @Binding var range: HistoryRange
    @Binding var metric: HistoryView.Metric

    var body: some View {
        HStack {
            Picker("", selection: $range) {
                ForEach(HistoryRange.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            Spacer()
            // A menu, not a segmented control: eight metrics would overflow a segment row.
            Picker(selection: $metric) {
                ForEach(HistoryView.Metric.allCases) { m in
                    Label(m.title, systemImage: m.symbol).tag(m)
                }
            } label: {
                Label(metric.title, systemImage: metric.symbol)
            }
            .pickerStyle(.menu).labelsHidden().fixedSize()
        }
    }
}

// MARK: - Chart

private struct HistoryChartCard: View {
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
                .init(name: "Average", color: .orange) { settings.display($0.avgTemp) },
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
                .init(name: "Upload", color: .orange) { $0.netOutBps.map { $0 / 1_000_000 } },
            ]
        case .disk:
            return [
                .init(name: "Read", color: .yellow) { $0.diskReadBps.map { $0 / 1_000_000 } },
                .init(name: "Write", color: .orange) { $0.diskWriteBps.map { $0 / 1_000_000 } },
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

// MARK: - Stats

private struct HistoryStatsCard: View {
    @Environment(AppSettings.self) private var settings
    let samples: [HistorySample]
    let metric: HistoryView.Metric

    var body: some View {
        let readings = values
        SectionCard(title: "Summary", symbol: "function") {
            HStack(spacing: 24) {
                statColumn("Low", text(readings.min()))
                statColumn("Average", text(readings.isEmpty ? nil : readings.reduce(0, +) / Double(readings.count)))
                statColumn("Peak", text(readings.max()))
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(samples.count) points").font(.caption).foregroundStyle(.secondary)
                    if let first = samples.first?.time, let last = samples.last?.time {
                        Text("\(first.formatted(.dateTime.month().day().hour().minute())) – \(last.formatted(.dateTime.hour().minute()))")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    /// The primary series for the selected metric (download for network, read for
    /// disk). The chart shows both directions; the summary follows the headline one.
    private var values: [Double] {
        switch metric {
        case .temp:    return samples.map(\.hottestTemp)
        case .cpu:     return samples.map(\.cpuUsage)
        case .gpu:     return samples.compactMap(\.gpuUsage)
        case .memory:  return samples.map(\.memoryGB)
        case .network: return samples.compactMap(\.netInBps)
        case .disk:    return samples.compactMap(\.diskReadBps)
        case .battery: return samples.compactMap(\.batteryPercent)
        case .power:   return samples.compactMap(\.socWatts)
        }
    }

    private func text(_ value: Double?) -> String {
        guard let value else { return "—" }
        switch metric {
        case .temp:   return settings.format(value, decimals: 0)
        case .cpu, .gpu, .battery: return "\(Int(value.rounded()))%"
        case .memory: return String(format: "%.1f GB", value)
        case .network, .disk: return NetworkFormat.rate(value)
        case .power:  return String(format: "%.1f W", value)
        }
    }
}

// MARK: - Export

private struct HistoryExportCard: View {
    @State private var message: String?

    var body: some View {
        SectionCard(title: "Export", symbol: "square.and.arrow.up") {
            HStack(spacing: 8) {
                Button("Export CSV") { export(.csv) }
                Button("Export JSON") { export(.json) }
                if let message {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .controlSize(.small)
            Text("Saves the full log to \((DataHome.exportsDirectory.path as NSString).abbreviatingWithTildeInPath) and reveals it in Finder.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private enum Format { case csv, json }

    private func export(_ format: Format) {
        Task {
            let url = await Task.detached(priority: .userInitiated) {
                switch format {
                case .csv: return HistoryExport.csv()
                case .json: return HistoryExport.json()
                }
            }.value
            if let url {
                NSWorkspace.shared.activateFileViewerSelecting([url])
                message = "Saved \(url.lastPathComponent)"
            } else {
                message = "Nothing to export yet"
            }
        }
    }
}

// MARK: - Recent alerts

private struct AlertHistoryCard: View {
    let events: [AlertEvent]

    var body: some View {
        SectionCard(title: "Recent alerts", symbol: "bell.badge") {
            VStack(spacing: 10) {
                ForEach(events) { event in
                    HStack(alignment: .top, spacing: 10) {
                        IconTile(symbol: "bell.fill", tint: .orange, size: 22, font: .caption, cornerRadius: 6)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(event.message)
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(event.time.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                        Spacer(minLength: 0)
                    }
                    if event.id != events.last?.id { Divider().opacity(0.5) }
                }
            }
        }
    }
}
