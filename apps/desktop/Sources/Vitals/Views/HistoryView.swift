import SwiftUI
import Charts
import AppKit

/// The History tab: a browsable timeline of the logged readings, zoomable to the
/// last hour/day/week or everything. Reads the CSV off-main and only while the
/// tab is open, so it never costs anything in the background. History logging is
/// off by default, so the empty state invites turning it on.
struct HistoryView: View {
    @EnvironmentObject private var settings: AppSettings
    let isActive: Bool

    @State private var range: HistoryRange = .day
    @State private var metric: Metric = .temp
    @State private var samples: [HistorySample] = []
    @State private var loading = false

    enum Metric: String, CaseIterable, Identifiable {
        case temp, cpu, gpu, memory
        var id: String { rawValue }
        var title: String {
            switch self {
            case .temp: return "Temp"
            case .cpu: return "CPU"
            case .gpu: return "GPU"
            case .memory: return "Memory"
            }
        }
    }

    private struct ReloadKey: Equatable { let active: Bool; let range: HistoryRange; let logging: Bool }

    var body: some View {
        MetricScroll {
            if !samples.isEmpty {
                // Existing history is browsable even if logging was since turned
                // off — flag that it won't keep growing.
                if !settings.loggingEnabled { loggingPausedNote }
                HistoryControls(range: $range, metric: $metric)
                HistoryChartCard(samples: samples, metric: metric, range: range)
                HistoryStatsCard(samples: samples, metric: metric)
                HistoryExportCard()
            } else if loading {
                emptyState
            } else if !settings.loggingEnabled {
                loggingOffState
            } else {
                emptyState
            }
        }
        .task(id: ReloadKey(active: isActive, range: range, logging: settings.loggingEnabled)) {
            await reload()
        }
    }

    private func reload() async {
        guard isActive else { return }              // keep what we have when off-tab
        loading = true
        let range = self.range
        let loaded = await Task.detached(priority: .userInitiated) {
            HistoryReader.load(range: range, now: Date())
        }.value
        guard !Task.isCancelled else { return }     // a newer reload superseded this one
        samples = loaded
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
            Picker("", selection: $range) {
                ForEach(HistoryRange.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            Spacer()
            Picker("", selection: $metric) {
                ForEach(HistoryView.Metric.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
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
            }
        }
        .chartForegroundStyleScale(domain: metric == .temp ? ["Average", "Hottest"] : [],
                                   range: [Color.orange, .red.opacity(0.7)])
        .chartLegend(metric == .temp ? .visible : .hidden)
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

    private var yLabel: String {
        switch metric {
        case .temp: return settings.unit.symbol
        case .cpu, .gpu: return "%"
        case .memory: return "GB"
        }
    }

    private var yDomain: ClosedRange<Double> {
        switch metric {
        case .cpu, .gpu: return 0...100
        case .memory:
            let peak = samples.map(\.memoryGB).max() ?? 1
            return 0...max(peak * 1.1, 1)
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

    /// The primary series for the selected metric.
    private var values: [Double] {
        switch metric {
        case .temp:   return samples.map(\.hottestTemp)
        case .cpu:    return samples.map(\.cpuUsage)
        case .gpu:    return samples.compactMap(\.gpuUsage)
        case .memory: return samples.map(\.memoryGB)
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
        case .cpu, .gpu: return "\(Int(value.rounded()))%"
        case .memory: return String(format: "%.1f GB", value)
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
            Text("Saves the full log to ~/.vitals/exports and reveals it in Finder.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private enum Format { case csv, json }

    private func export(_ format: Format) {
        Task {
            let url = await Task.detached(priority: .userInitiated) {
                format == .csv ? HistoryExport.csv() : HistoryExport.json()
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
