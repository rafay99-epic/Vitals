import SwiftUI

/// GPU utilization with a usage sparkline. Mirrors `CPUUsageWidget`.
struct GPUWidget: View {
    @EnvironmentObject private var model: VitalsModel
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.widgetScale) private var scale

    var body: some View {
        WidgetCard(title: "GPU", symbol: "cpu.fill", tint: .purple,
                   intensity: (model.gpu?.utilization ?? 0) / 100) {
            HStack(alignment: .firstTextBaseline, spacing: 6 * scale) {
                Text(model.gpu?.utilization.map { String(format: "%.0f%%", $0) } ?? "—")
                    .scaledFont(30, weight: .semibold, design: .rounded)
                    .monospacedDigit()
                    .numericTransition()
                Spacer(minLength: 0)
                Text(detail)
                    .scaledFont(10.5)
                    .foregroundStyle(.secondary)
            }
            WidgetSparkline(values: model.chartHistory.suffix(40).compactMap(\.gpuUsage), tint: .purple)
                .frame(maxHeight: .infinity)
                .frame(minHeight: 22 * scale)
        }
    }

    /// Prefer temperature, fall back to memory in use — whichever we can read.
    private var detail: String {
        if let temp = model.gpuTemp {
            return settings.formatWithUnit(temp, decimals: 0)
        }
        if let used = model.gpu?.memoryUsed {
            return String(format: "%.1f GB", gigabytes(used))
        }
        return ""
    }
}
