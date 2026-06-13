import SwiftUI

/// A wider at-a-glance card: CPU temperature, CPU usage, memory, and fan in one
/// panel. Reads the shared `VitalsModel`.
struct CombinedWidget: View {
    @EnvironmentObject private var model: VitalsModel
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        WidgetCard(title: "Vitals", symbol: "gauge.with.dots.needle.50percent", tint: .green) {
            Grid(horizontalSpacing: 14, verticalSpacing: 7) {
                GridRow {
                    metric("CPU", cpuTemp, "cpu", cpuTint)
                    metric("Usage", String(format: "%.0f%%", model.cpuUsage), "gauge.with.dots.needle.50percent", .blue)
                }
                GridRow {
                    metric("Memory", memoryValue, "memorychip", memoryTint)
                    metric("Fan", fanValue, "fan", .cyan)
                }
            }
        }
    }

    private var cpuTint: Color { model.averageCPUTemp.map(tempGradientColor) ?? .secondary }
    private var cpuTemp: String { model.averageCPUTemp.map { settings.format($0, decimals: 0) } ?? "—" }
    private var memoryTint: Color { model.memory.map { pressureColor($0.pressure) } ?? .indigo }
    private var memoryValue: String { model.memory.map { String(format: "%.1f GB", gigabytes($0.used)) } ?? "—" }
    private var fanValue: String {
        guard model.hasSMC else { return "—" }
        guard let fan = model.fans.first else { return "Fanless" }
        return "\(Int(fan.rpm))"
    }

    private func metric(_ label: String, _ value: String, _ symbol: String, _ tint: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .frame(width: 20, height: 20)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(tint.opacity(0.16)))
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.tertiary)
                Text(value)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
