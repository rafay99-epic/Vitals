import SwiftUI

/// Overall CPU utilization with a usage sparkline.
struct CPUUsageWidget: View {
    @EnvironmentObject private var model: VitalsModel
    @Environment(\.widgetScale) private var scale

    var body: some View {
        WidgetCard(title: "CPU Usage", symbol: "gauge.with.dots.needle.50percent", tint: .blue,
                   intensity: model.cpuUsage / 100) {
            HStack(alignment: .firstTextBaseline, spacing: 6 * scale) {
                Text(String(format: "%.0f%%", model.cpuUsage))
                    .scaledFont(30, weight: .semibold, design: .rounded)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Spacer(minLength: 0)
                Text(model.thermalState.label)
                    .scaledFont(10.5)
                    .foregroundStyle(model.thermalState.tint)
            }
            WidgetSparkline(values: model.chartHistory.suffix(40).map(\.usage), tint: .blue)
                .frame(maxHeight: .infinity)
                .frame(minHeight: 22 * scale)
        }
    }
}
