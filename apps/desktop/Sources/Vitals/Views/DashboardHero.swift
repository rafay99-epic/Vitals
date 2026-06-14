import SwiftUI

/// The dashboard's at-a-glance row: the handful of vitals worth seeing first,
/// in one balanced line of equal-width tiles (a single HStack, so it never
/// orphans a tile the way the old wrapping grid did). Reuses `StatCard`.
struct DashboardHero: View {
    @EnvironmentObject private var model: VitalsModel
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        HStack(spacing: 12) {
            StatCard(
                title: "CPU",
                value: model.averageCPUTemp.map { settings.format($0) } ?? "—",
                subtitle: cpuSubtitle,
                symbol: "cpu",
                tint: model.averageCPUTemp.map(tempGradientColor) ?? .secondary
            )
            StatCard(
                title: "CPU Load",
                value: String(format: "%.0f%%", model.cpuUsage),
                subtitle: "\(HardwareInfo.coreCount) cores",
                symbol: "gauge.with.dots.needle.50percent",
                tint: .blue
            )
            if let gpu = model.gpu {
                StatCard(
                    title: "GPU",
                    value: gpu.utilization.map { String(format: "%.0f%%", $0) } ?? "—",
                    subtitle: gpuSubtitle(gpu),
                    symbol: "cpu.fill",
                    tint: .purple
                )
            }
            StatCard(
                title: "Memory",
                value: String(format: "%.1f GB", gigabytes(model.memory?.used ?? 0)),
                subtitle: memorySubtitle,
                symbol: "memorychip",
                tint: model.memory.map { pressureColor($0.pressure) } ?? .indigo
            )
            StatCard(
                title: "Thermal",
                value: model.thermalState.label,
                subtitle: "Reported by macOS",
                symbol: "thermometer.medium",
                tint: model.thermalState.tint
            )
        }
    }

    private var cpuSubtitle: String {
        guard let hottest = model.hottestCPUSensor else { return "\(model.cpuSensors.count) sensors" }
        return "Hottest \(settings.format(hottest.celsius, decimals: 0)) · \(hottest.label)"
    }

    private func gpuSubtitle(_ gpu: GPUSnapshot) -> String {
        if let used = gpu.memoryUsed { return String(format: "%.1f GB memory", gigabytes(used)) }
        return gpu.name ?? "GPU"
    }

    private var memorySubtitle: String {
        guard let memory = model.memory else { return "—" }
        return String(format: "of %.0f GB · %@", gigabytes(memory.total), memory.pressure.label)
    }
}
