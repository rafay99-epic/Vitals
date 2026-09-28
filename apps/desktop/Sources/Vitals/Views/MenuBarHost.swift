import SwiftUI
import AppKit

/// The menu-bar status item's label, hosted live in `MenuBarController`'s
/// status item. `.fixedSize()` pins it to its ideal width so the controller can
/// size the item to it without truncating (issues #45, #50). Static on purpose:
/// see `MenuBarController` for why nothing here animates.
struct MenuBarLabelView: View {
    @Environment(VitalsModel.self) private var model
    @Environment(AppSettings.self) private var settings

    private var metrics: [MenuBarMetric] {
        MenuBarMetric.allCases.filter(settings.menuBarMetrics.contains)
    }
    private var warning: Bool {
        model.averageCPUTemp.map { $0 >= settings.warnThreshold } ?? false
    }

    var body: some View {
        content
            .fixedSize()
            .padding(.horizontal, 3)
            .frame(maxHeight: .infinity)            // fill the bar height, center vertically
            // labelColor resolves against the menu bar's appearance, so the
            // readout stays legible whether the bar is light or dark.
            .foregroundStyle(Color(nsColor: .labelColor))
    }

    @ViewBuilder
    private var content: some View {
        if metrics.isEmpty {
            Image(systemName: warning ? "flame.fill" : "thermometer.medium")
        } else if settings.menuBarUseIcons {
            MenuBarRow(metrics: metrics, warning: warning)
        } else {
            // Text style: short word + value, e.g. "Temp 57° · CPU 23% · RAM 12.8G".
            Text(metrics.map { "\($0.shortLabel) \(menuBarValue($0, model: model, settings: settings))" }
                .joined(separator: " · "))
                .monospacedDigit()
                .lineLimit(1)
        }
    }
}

/// The icon + value row.
private struct MenuBarRow: View {
    @Environment(VitalsModel.self) private var model
    @Environment(AppSettings.self) private var settings
    let metrics: [MenuBarMetric]
    let warning: Bool

    var body: some View {
        HStack(spacing: 6) {
            ForEach(metrics) { metric in
                HStack(spacing: 3) {
                    Image(systemName: metric == .cpuTemp && warning ? "flame.fill" : metric.symbol)
                    Text(menuBarValue(metric, model: model, settings: settings))
                        .monospacedDigit()
                        .lineLimit(1)
                        // Throughput strings change width every tick ("↓983B" →
                        // "↓3.1M"), and each change re-fits the whole status bar.
                        // A slot sized for the common case absorbs the churn.
                        .frame(minWidth: [.network, .disk].contains(metric) ? 44 : 0, alignment: .leading)
                }
            }
        }
        .font(.system(size: 13))
    }
}

/// The live reading for one metric. A dash (never a fabricated value) stands in
/// when a subsystem isn't present or hasn't reported yet.
@MainActor
func menuBarValue(_ metric: MenuBarMetric, model: VitalsModel, settings: AppSettings) -> String {
    switch metric {
    case .cpuTemp:  return model.averageCPUTemp.map { settings.format($0, decimals: 0) } ?? "–"
    case .cpuUsage: return "\(Int(model.cpuUsage.rounded()))%"
    case .gpuUsage: return model.gpu?.utilization.map { "\(Int($0.rounded()))%" } ?? "–"
    case .memory:   return model.memory.map { String(format: "%.1fG", Double($0.used) / 1_073_741_824) } ?? "–"
    case .fan:      return model.fans.first.map { "\(Int($0.rpm))" } ?? "–"
    case .network:  return model.network.map { "↓" + NetworkFormat.compactRate($0.totalInPerSec) } ?? "–"
    case .disk:     return model.diskIO.map { "R" + NetworkFormat.compactRate($0.readPerSec) } ?? "–"
    }
}
