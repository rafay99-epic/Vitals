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
