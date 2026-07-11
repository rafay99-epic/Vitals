import SwiftUI
import Charts
import AppKit

/// The History tab: a browsable timeline of the logged readings, zoomable to the
/// last hour/day/week or everything. Queries the SQLite store off-main and only
/// while the tab is open, so it never costs anything in the background. Logging is
/// on by default; if the user turns it off, the empty state invites turning it
/// back on.
struct HistoryView: View {
    @EnvironmentObject private var settings: AppSettings
    let isActive: Bool

    @State private var range: HistoryRange = .day
    @State private var metric: Metric = LaunchOverrides.historyMetric ?? .temp
    @State private var samples: [HistorySample] = []
    @State private var alertEvents: [AlertEvent] = []
    @State private var loading = false

    enum Metric: String, CaseIterable, Identifiable {
        case temp, cpu, gpu, memory, network, disk, battery, power
        var id: String { rawValue }
        var title: String {
            switch self {
            case .temp: return "Temp"
            case .cpu: return "CPU"
            case .gpu: return "GPU"
            case .memory: return "Memory"
            case .network: return "Network"
            case .disk: return "Disk"
            case .battery: return "Battery"
            case .power: return "Power"
            }
        }
        /// SF Symbol matching the sidebar, so the metric menu reads at a glance.
        var symbol: String {
            switch self {
            case .temp: return "thermometer.medium"
            case .cpu: return "cpu"
            case .gpu: return "cpu.fill"
            case .memory: return "memorychip"
            case .network: return "network"
            case .disk: return "internaldrive"
            case .battery: return "battery.100percent"
            case .power: return "bolt.fill"
            }
        }
    }

    private struct ReloadKey: Equatable { let active: Bool; let range: HistoryRange; let logging: Bool }

    var body: some View {
        MetricScroll {
            timeline
            // Fired alerts are independent of the metric log, so they show even
            // when logging is off and the chart is empty.
            if !alertEvents.isEmpty {
                AlertHistoryCard(events: alertEvents)
            }
            // Export lives outside the samples gate: per-app energy is logged
            // independently of CPU-temp samples, so its CSV must stay reachable
            // even on a Mac whose main history chart is empty.
            HistoryExportCard()
        }
        .task(id: ReloadKey(active: isActive, range: range, logging: settings.loggingEnabled)) {
            await reload()
        }
    }

    @ViewBuilder
    private var timeline: some View {
        if !samples.isEmpty {
            // Existing history is browsable even if logging was since turned
            // off — flag that it won't keep growing.
            if !settings.loggingEnabled { loggingPausedNote }
            HistoryControls(range: $range, metric: $metric)
            HistoryChartCard(samples: samples, metric: metric, range: range)
            HistoryStatsCard(samples: samples, metric: metric)
        } else if loading {
            emptyState
        } else if !settings.loggingEnabled {
            loggingOffState
        } else {
            emptyState
        }
    }

    private func reload() async {
        guard isActive else { return }              // keep what we have when off-tab
        loading = true
        let range = self.range
        let result = await Task.detached(priority: .userInitiated) {
            (HistoryReader.load(range: range, now: Date()), AlertLog.recent(limit: 30))
        }.value
        guard !Task.isCancelled else { return }     // a newer reload superseded this one
        samples = result.0
        alertEvents = result.1
        loading = false
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
            message: "Turn on logging to record temperatures, usage, fans, and more to ~/.vitals — then browse and export the timeline here. It writes one line every 10 seconds."
        ) {
            Button("Turn On Logging") { settings.loggingEnabled = true }
                .buttonStyle(.borderedProminent)
        }
    }

    private var emptyState: some View {
        EmptyStateView(
            symbol: loading ? "hourglass" : "clock.arrow.circlepath",
            tint: .indigo,
            title: loading ? "Reading history…" : "No history yet",
            message: loading
                ? "Loading the logged readings."
                : "Logging is on, but nothing's been recorded for this range yet. Check back in a few minutes."
        ) { EmptyView() }
    }
}

// MARK: - Controls

private struct HistoryControls: View {
    @Binding var range: HistoryRange
    @Binding var metric: HistoryView.Metric

    var body: some View {
        HStack {
            // Time range stays a segmented control — only four options, and quick
            // side-by-side switching is the common action.
            Picker("", selection: $range) {
                ForEach(HistoryRange.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            Spacer()
            // Metric is a menu, not a segment row: eight-plus metrics would crowd
            // (and eventually overflow) a segmented control. The menu scales to any
            // number and shows the current pick with its icon.
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
    @EnvironmentObject private var settings: AppSettings
    let samples: [HistorySample]
    let metric: HistoryView.Metric
    let range: HistoryRange

    var body: some View {
        SectionCard(title: rangeTitle, symbol: "chart.xyaxis.line") {
            Deferred { chart }
                .frame(height: 240)
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
        Chart {
            switch metric {
            case .temp:
                ForEach(samples) { s in
                    LineMark(x: .value("Time", s.time), y: .value("Temp", settings.display(s.hottestTemp)),
                             series: .value("S", "Hottest"))
                        .foregroundStyle(by: .value("S", "Hottest")).interpolationMethod(.catmullRom)
                    LineMark(x: .value("Time", s.time), y: .value("Temp", settings.display(s.avgTemp)),
                             series: .value("S", "Average"))
                        .foregroundStyle(by: .value("S", "Average")).interpolationMethod(.catmullRom)
                }
            case .cpu:
                ForEach(samples) { s in areaLine(s.time, s.cpuUsage, .blue) }
            case .gpu:
                ForEach(samples) { s in if let g = s.gpuUsage { areaLine(s.time, g, .purple) } }
            case .memory:
                ForEach(samples) { s in
                    LineMark(x: .value("Time", s.time), y: .value("GB", s.memoryGB))
                        .foregroundStyle(.indigo).interpolationMethod(.catmullRom)
                }
            case .network:
                ForEach(samples) { s in
                    if let down = s.netInBps {
                        LineMark(x: .value("Time", s.time), y: .value("MB/s", down / 1_000_000),
                                 series: .value("S", "Download"))
                            .foregroundStyle(by: .value("S", "Download")).interpolationMethod(.catmullRom)
                    }
                    if let up = s.netOutBps {
                        LineMark(x: .value("Time", s.time), y: .value("MB/s", up / 1_000_000),
                                 series: .value("S", "Upload"))
                            .foregroundStyle(by: .value("S", "Upload")).interpolationMethod(.catmullRom)
                    }
                }
            case .disk:
                ForEach(samples) { s in
                    if let read = s.diskReadBps {
                        LineMark(x: .value("Time", s.time), y: .value("MB/s", read / 1_000_000),
                                 series: .value("S", "Read"))
                            .foregroundStyle(by: .value("S", "Read")).interpolationMethod(.catmullRom)
                    }
                    if let write = s.diskWriteBps {
                        LineMark(x: .value("Time", s.time), y: .value("MB/s", write / 1_000_000),
                                 series: .value("S", "Write"))
                            .foregroundStyle(by: .value("S", "Write")).interpolationMethod(.catmullRom)
                    }
                }
            case .battery:
                ForEach(samples) { s in if let b = s.batteryPercent { areaLine(s.time, b, .green) } }
            case .power:
                ForEach(samples) { s in
                    if let w = s.socWatts {
                        LineMark(x: .value("Time", s.time), y: .value("W", w))
                            .foregroundStyle(.orange).interpolationMethod(.catmullRom)
                    }
                }
            }
        }
        .chartForegroundStyleScale(domain: seriesStyle.domain, range: seriesStyle.range)
        .chartLegend(metric == .temp || metric == .network || metric == .disk ? .visible : .hidden)
        .chartYScale(domain: yDomain)
        .chartYAxisLabel(yLabel)
    }

    @ChartContentBuilder
    private func areaLine(_ time: Date, _ value: Double, _ color: Color) -> some ChartContent {
        AreaMark(x: .value("Time", time), y: .value("%", value))
            .foregroundStyle(LinearGradient(colors: [color.opacity(0.32), color.opacity(0.02)],
                                            startPoint: .top, endPoint: .bottom))
            .interpolationMethod(.catmullRom)
        LineMark(x: .value("Time", time), y: .value("%", value))
            .foregroundStyle(color).interpolationMethod(.catmullRom)
    }

    /// Legend/color domain for the current metric (empty for the single-series
    /// views, which colour their marks directly).
    private var seriesStyle: (domain: [String], range: [Color]) {
        switch metric {
        case .temp:    return (["Average", "Hottest"], [.orange, .red.opacity(0.7)])
        case .network: return (["Download", "Upload"], [.mint, .orange])
        case .disk:    return (["Read", "Write"], [.yellow, .orange])
        case .cpu, .gpu, .memory, .battery, .power: return ([], [])
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

    private var yDomain: ClosedRange<Double> {
        switch metric {
        case .cpu, .gpu, .battery: return 0...100
        case .power:
            let peak = samples.compactMap(\.socWatts).max() ?? 1
            return 0...max(peak * 1.1, 1)
        case .memory:
            let peak = samples.map(\.memoryGB).max() ?? 1
            return 0...max(peak * 1.1, 1)
        case .network:
            // Peak of either direction in MB/s; the small floor keeps an idle
            // link's noise from stretching across the full chart height.
            let rates = samples.flatMap { [$0.netInBps, $0.netOutBps].compactMap { $0 } }
            return 0...max(((rates.max() ?? 0) / 1_000_000) * 1.1, 0.1)
        case .disk:
            // Same idea as network: peak of either direction in MB/s, with a
            // small floor so an idle drive's noise doesn't fill the chart.
            let rates = samples.flatMap { [$0.diskReadBps, $0.diskWriteBps].compactMap { $0 } }
            return 0...max(((rates.max() ?? 0) / 1_000_000) * 1.1, 0.1)
        case .temp:
            let temps = samples.flatMap { [$0.avgTemp, $0.hottestTemp] }.map(settings.display)
            guard let lo = temps.min(), let hi = temps.max() else { return settings.display(30)...settings.display(90) }
            return (lo - 5)...(hi + 5)
        }
    }
}

// MARK: - Stats

private struct HistoryStatsCard: View {
    @EnvironmentObject private var settings: AppSettings
    let samples: [HistorySample]
    let metric: HistoryView.Metric

    var body: some View {
        SectionCard(title: "Summary", symbol: "function") {
            HStack(spacing: 24) {
                stat("Low", values.min())
                stat("Average", values.isEmpty ? nil : values.reduce(0, +) / Double(values.count))
                stat("Peak", values.max())
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

    /// The primary series for the selected metric (download, for network;
    /// read, for disk — the chart shows both directions, the summary follows
    /// the headline one).
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

    private func stat(_ label: String, _ value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value.map(format) ?? "—")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
    }

    private func format(_ value: Double) -> String {
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
                Button("App Energy CSV") { export(.appEnergy) }
                if let message {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .controlSize(.small)
            Text("Saves the full log to ~/.vitals/exports and reveals it in Finder.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private enum Format { case csv, json, appEnergy }

    private func export(_ format: Format) {
        Task {
            let url = await Task.detached(priority: .userInitiated) {
                switch format {
                case .csv: return HistoryExport.csv()
                case .json: return HistoryExport.json()
                case .appEnergy: return HistoryExport.appEnergyCSV()
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
                        Image(systemName: "bell.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .frame(width: 22, height: 22)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.orange.opacity(0.14)))
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
