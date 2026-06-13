import SwiftUI

/// Overall CPU utilization with a usage sparkline.
struct CPUUsageWidget: View {
    @EnvironmentObject private var model: VitalsModel

    var body: some View {
        WidgetCard(title: "CPU Usage", symbol: "gauge.with.dots.needle.50percent", tint: .blue) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(String(format: "%.0f%%", model.cpuUsage))
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Spacer(minLength: 0)
                Text(model.thermalState.label)
                    .font(.caption2)
                    .foregroundStyle(model.thermalState.tint)
            }
            WidgetSparkline(values: model.chartHistory.suffix(40).map(\.usage), tint: .blue)
                .frame(height: 22)
        }
    }
}
