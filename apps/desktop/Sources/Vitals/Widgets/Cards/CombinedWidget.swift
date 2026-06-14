import SwiftUI

/// A wider at-a-glance card: CPU temperature, CPU usage, memory, and fan in one
/// panel. Reads the shared `VitalsModel`.
struct CombinedWidget: View {
    @EnvironmentObject private var model: VitalsModel
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.widgetScale) private var scale

    var body: some View {
        WidgetCard(title: "Vitals", symbol: "gauge.with.dots.needle.50percent", tint: .green,
                   intensity: overallIntensity) {
            Grid(horizontalSpacing: 14 * scale, verticalSpacing: 7 * scale) {
                GridRow {
                    metric("CPU", cpuTemp, "cpu", cpuTint)
                    metric("Usage", String(format: "%.0f%%", model.cpuUsage), "gauge.with.dots.needle.50percent", .blue)
                }
                GridRow {
                    metric("Memory", memoryValue, "memorychip", memoryTint)
                    metric("Fan", fanValue, "fan", .cyan)
                }
                if model.gpu != nil {
                    GridRow {
                        metric("GPU", gpuValue, "cpu.fill", .purple)
                        metric("GPU °", gpuTemp, "thermometer.medium", gpuTempTint)
                    }
                }
            }
        }
    }

    /// Overall system stress: the worst of CPU heat, CPU load, and memory
    /// pressure — so the at-a-glance card glows for whatever's actually loaded.
    private var overallIntensity: Double {
        max(model.averageCPUTemp.map(tempSeverity) ?? 0,
            max(model.cpuUsage / 100, model.memory?.usedFraction ?? 0))
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
    private var gpuValue: String { model.gpu?.utilization.map { String(format: "%.0f%%", $0) } ?? "—" }
    private var gpuTemp: String { model.gpuTemp.map { settings.format($0, decimals: 0) } ?? "—" }
    private var gpuTempTint: Color { model.gpuTemp.map(tempGradientColor) ?? .secondary }

    private func metric(_ label: String, _ value: String, _ symbol: String, _ tint: Color) -> some View {
        HStack(spacing: 7 * scale) {
            Image(systemName: symbol)
                .scaledFont(10, weight: .medium)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .frame(width: 20 * scale, height: 20 * scale)
                .background(RoundedRectangle(cornerRadius: 5 * scale, style: .continuous).fill(tint.opacity(0.16)))
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .scaledFont(9.5, weight: .medium)
                    .foregroundStyle(.tertiary)
                Text(value)
                    .scaledFont(16, weight: .semibold, design: .rounded)
                    .monospacedDigit()
                    .numericTransition()
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
