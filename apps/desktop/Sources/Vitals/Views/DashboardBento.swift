import SwiftUI

// The Dashboard's overview surfaces: a health-score hero, the bento tile grid,
// and the top-processes card. Each is a drill-in — tapping jumps to the matching
// System segment. Honest throughout: a tile with no data yet simply omits its
// sparkline rather than drawing a fabricated line, and an absent subsystem (no
// GPU, no battery) drops its tile entirely.

// MARK: - Health hero

/// The single synthesizing read at the top: an honest "is my Mac OK right now?"
/// verdict — the worst of macOS's thermal state, the hottest CPU sensor, memory
/// pressure and cooling — beside the machine's identity. Reuses `SystemHealth`
/// (the same classification the Sensors signals use), inventing no score. Tapping
/// opens System ▸ Sensors for the full breakdown.
struct DashboardHealthHero: View {
    @EnvironmentObject private var model: VitalsModel
    let drill: (SystemView.Segment) -> Void
    @State private var hovered = false

    var body: some View {
        let level = overallLevel
        let throttling = SystemHealth.isThrottling(model.thermalState)
        Button { drill(.sensors) } label: {
            HStack(spacing: 16) {
                ZStack {
                    Circle().fill(level.tint.opacity(0.16)).frame(width: 60, height: 60)
                    Image(systemName: throttling ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 26, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(level.tint)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(SystemHealth.headline(level: level, throttling: throttling))
                        .font(.system(size: 20, weight: .semibold))
                    Text(identityLine)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(hovered ? AnyShapeStyle(.secondary) : AnyShapeStyle(.quaternary))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .cardBackground()
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help("Open System ▸ Sensors")
    }

    /// The verdict: the worst level across every signal we can read. Identical
    /// composition to the Sensors signals — one source of truth, never two.
    private var overallLevel: SystemHealth.Level {
        var levels: [SystemHealth.Level] = [SystemHealth.thermalLevel(model.thermalState)]
        if let hottest = model.hottestCPUSensor {
            levels.append(SystemHealth.temperatureLevel(celsius: hottest.celsius))
        }
        if let memory = model.memory {
            levels.append(SystemHealth.pressureLevel(memory.pressure))
        }
        if !model.fans.isEmpty {
            levels.append(model.fans.map { SystemHealth.fanLevel(rpm: $0.rpm, maxRPM: $0.maxRPM) }.max() ?? .good)
        }
        return levels.max() ?? .good
    }

    private var identityLine: String {
        var parts = [HardwareInfo.chipName]
        if let memory = model.memory { parts.append(String(format: "%.0f GB", gigabytes(memory.total))) }
        parts.append(HardwareInfo.osVersion)
        parts.append("Up \(HardwareInfo.uptimeText)")
        return parts.joined(separator: " · ")
    }
}

// MARK: - Bento tile grid

/// The glance: one tile per subsystem in a fixed three-column grid (never
/// adaptive, per the performance rules). Each tile shows the headline number, a
/// 60-sample sparkline, and drills into its System segment. Tiles for absent
/// hardware (no GPU, no battery, no SMART) are simply omitted.
struct DashboardTileGrid: View {
    @EnvironmentObject private var model: VitalsModel
    @EnvironmentObject private var settings: AppSettings
    let drill: (SystemView.Segment) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            DashboardTile(
                title: "CPU",
                value: model.averageCPUTemp.map { settings.format($0) } ?? "—",
                subtitle: String(format: "%.0f%% load · %d cores", model.cpuUsage, HardwareInfo.coreCount),
                symbol: "cpu",
                tint: model.averageCPUTemp.map(tempGradientColor) ?? .secondary,
                series: recent { $0.averageCPU }
            ) { drill(.cpu) }

            if let gpu = model.gpu {
                DashboardTile(
                    title: "GPU",
                    value: gpu.utilization.map { String(format: "%.0f%%", $0) } ?? "—",
                    subtitle: gpuSubtitle(gpu),
                    symbol: "cpu.fill",
                    tint: .purple,
                    series: recentCompact { $0.gpuUsage }
                ) { drill(.gpu) }
            }

            DashboardTile(
                title: "Memory",
                value: model.memory.map { String(format: "%.1f GB", gigabytes($0.used)) } ?? "—",
                subtitle: memorySubtitle,
                symbol: "memorychip",
                tint: model.memory.map { pressureColor($0.pressure) } ?? .indigo,
                series: recent { $0.memoryUsed }
            ) { drill(.memory) }

            if let battery = model.battery {
                DashboardTile(
                    title: "Battery",
                    value: "\(Int(battery.percent))%",
                    subtitle: batterySubtitle(battery),
                    symbol: BatteryContent.symbol(for: battery),
                    tint: batteryTint(battery),
                    series: recentCompact { $0.batteryPercent }
                ) { drill(.battery) }
            }

            if let disk = model.diskHealth {
                DashboardTile(
                    title: "Drive",
                    value: "\(disk.percentUsed)%",
                    subtitle: "of write endurance · \(DiskHealthSnapshot.condition(criticalWarning: disk.criticalWarning))",
                    symbol: DiskContent.symbol(for: disk),
                    tint: diskWearTint(disk.wearLevel)
                ) { drill(.sensors) }
            }

            DashboardTile(
                title: "Thermal",
                value: model.thermalState.label,
                subtitle: "Reported by macOS",
                symbol: "thermometer.medium",
                tint: model.thermalState.tint
            ) { drill(.sensors) }
        }
    }

    /// The most recent ~60 samples for a sparkline — short enough to read as
    /// "right now", long enough to show a trend.
    private func recent(_ key: (VitalsModel.Sample) -> Double) -> [Double] {
        model.chartHistory.suffix(60).map(key)
    }
    private func recentCompact(_ key: (VitalsModel.Sample) -> Double?) -> [Double] {
        model.chartHistory.suffix(60).compactMap(key)
    }

    private func gpuSubtitle(_ gpu: GPUSnapshot) -> String {
        if let used = gpu.memoryUsed { return String(format: "%.1f GB memory", gigabytes(used)) }
        return gpu.name ?? "GPU"
    }

    private var memorySubtitle: String {
        guard let memory = model.memory else { return "—" }
        return String(format: "of %.0f GB · %@", gigabytes(memory.total), memory.pressure.label)
    }

    private func batterySubtitle(_ battery: BatterySnapshot) -> String {
        if battery.isCharging { return "Charging" }
        if battery.externalPower { return battery.fullyCharged ? "Fully charged" : "On power adapter" }
        if let minutes = battery.timeRemainingMinutes {
            return minutes < 60 ? "\(minutes) min left" : "\(minutes / 60) h \(minutes % 60) min left"
        }
        return "On battery"
    }

    private func batteryTint(_ battery: BatterySnapshot) -> Color {
        if battery.isCharging { return .green }
        switch battery.percent {
        case ..<20: return .red
        case ..<50: return .orange
        default: return .green
        }
    }
}

/// One bento tile: an icon-led header, a hero value, a one-line subtitle, and an
/// optional sparkline. The whole tile is the click target — it drills into the
/// matching System segment. A hover ring + chevron signal it's tappable.
struct DashboardTile: View {
    let title: String
    let value: String
    let subtitle: String
    let symbol: String
    let tint: Color
    var series: [Double] = []
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(tint)
                        .frame(width: 26, height: 26)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(tint.opacity(0.14)))
                    Text(title)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(hovered ? AnyShapeStyle(tint) : AnyShapeStyle(.quaternary))
                }
                Text(value)
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .numericTransition()
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                // A fixed-height slot so every tile is the same height whether or
                // not its sparkline has data yet.
                Group {
                    if series.count >= 2 {
                        WidgetSparkline(values: series, tint: tint)
                    } else {
                        Color.clear
                    }
                }
                .frame(height: 26)
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .cardBackground()
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(tint.opacity(hovered ? 0.5 : 0), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help("Open \(title) in System")
    }
}

// MARK: - Top processes

/// The live top-CPU processes, glanceable on the Dashboard (Mole puts them on the
/// status screen too). The whole card drills into System ▸ Processes — the full
/// sortable, searchable, quittable manager.
struct DashboardProcessesCard: View {
    let drill: (SystemView.Segment) -> Void
    @State private var hovered = false

    var body: some View {
        Button { drill(.processes) } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Label("Top processes", systemImage: "list.bullet.rectangle")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("All processes")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(hovered ? AnyShapeStyle(.secondary) : AnyShapeStyle(.quaternary))
                }
                TopProcessesContent()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .cardBackground()
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help("Open System ▸ Processes")
    }
}
