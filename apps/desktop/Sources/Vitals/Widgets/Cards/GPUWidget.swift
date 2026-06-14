import SwiftUI

/// GPU utilization with a usage sparkline. Mirrors `CPUUsageWidget`.
struct GPUWidget: View {
    @EnvironmentObject private var model: VitalsModel
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

    /// Memory in use — Apple Silicon exposes no GPU-specific temperature.
    private var detail: String {
        guard let used = model.gpu?.memoryUsed else { return "" }
        return String(format: "%.1f GB", gigabytes(used))
    }
}
