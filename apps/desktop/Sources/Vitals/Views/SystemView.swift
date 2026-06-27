import SwiftUI

/// The System tab: one canvas with a segmented filter over every hardware
/// deep-dive — the "details on demand" layer beneath the Dashboard's overview.
/// Mirrors Activity Monitor: switching a segment changes the content, never the
/// window geometry. Each metric that used to own a top-level tab (CPU, GPU,
/// Battery, History, Processes) is a segment here; the slow-moving hardware-health
/// readings (temperatures, fans, drive wear) are gathered under `Sensors`.
///
/// Segments mount lazily on first visit and stay alive for instant switch-back —
/// the same kept-alive approach as the top-level `TabCanvas`. Per-segment
/// `isActive` (this tab is up *and* this segment is selected) gates chart rebuilds
/// and process sampling, so a backgrounded segment costs nothing.
struct SystemView: View {
    /// Owned by `TabCanvas` so a scan started in the Processes segment survives
    /// switching tabs.
    @ObservedObject var processesModel: ProcessesModel
    /// True only while System is the visible tab.
    let isActive: Bool
    /// The selected segment, owned by `TabCanvas` so the Dashboard can drill
    /// straight to a specific subsystem (tap the CPU tile → System ▸ CPU) and so
    /// the choice survives tab switches.
    @Binding var segment: Segment
    @State private var visited: Set<Segment> = [.cpu]

    enum Segment: String, CaseIterable, Identifiable {
        case cpu, gpu, memory, battery, sensors, processes, history
        var id: String { rawValue }

        var title: String {
            switch self {
            case .cpu:       return "CPU"
            case .gpu:       return "GPU"
            case .memory:    return "Memory"
            case .battery:   return "Battery"
            case .sensors:   return "Sensors"
            case .processes: return "Processes"
            case .history:   return "History"
            }
        }

        var symbol: String {
            switch self {
            case .cpu:       return "cpu"
            case .gpu:       return "cpu.fill"
            case .memory:    return "memorychip"
            case .battery:   return "battery.100percent"
            case .sensors:   return "thermometer.medium"
            case .processes: return "list.bullet"
            case .history:   return "chart.xyaxis.line"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            SegmentControl(items: Segment.allCases, selection: $segment,
                           title: \.title, symbol: \.symbol,
                           onSelect: { visited.insert($0) })
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)
            Divider().opacity(0.5)
            canvas
        }
        // Mount whatever segment is selected — including one the Dashboard drilled
        // straight to, which never went through `onSelect`.
        .onChange(of: segment, initial: true) { _, seg in visited.insert(seg) }
    }

    // MARK: Canvas

    /// Segments mount lazily, then stay alive (kept-mounted, hidden) so switching
    /// back is instant. Switches are not animated — fading a translucent segment
    /// in over the glass window flashes dark before the blur resolves (same rule
    /// as `TabCanvas`); the indicator still springs, it lives in the bar above.
    private var canvas: some View {
        ZStack {
            if visited.contains(.cpu) {
                CPUView().tabVisibility(segment == .cpu)
            }
            if visited.contains(.gpu) {
                GPUView(isActive: active(.gpu)).tabVisibility(segment == .gpu)
            }
            if visited.contains(.memory) {
                MemoryView(isActive: active(.memory)).tabVisibility(segment == .memory)
            }
            if visited.contains(.battery) {
                BatteryView(isActive: active(.battery)).tabVisibility(segment == .battery)
            }
            if visited.contains(.sensors) {
                SensorsView().tabVisibility(segment == .sensors)
            }
            if visited.contains(.processes) {
                ProcessesView(model: processesModel, isActive: active(.processes))
                    .tabVisibility(segment == .processes)
            }
            if visited.contains(.history) {
                HistoryView(isActive: active(.history)).tabVisibility(segment == .history)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(nil, value: segment)
    }

    /// A segment is "active" only when System is the visible tab *and* this is the
    /// selected segment — the gate every kept-alive chart / sampler reads.
    private func active(_ seg: Segment) -> Bool { isActive && segment == seg }
}

// MARK: - Sensors segment

/// The hardware long-tail in one place (TG Pro's pattern): every temperature, the
/// fans and their control, and the internal drive's SMART health — plus a
/// one-click diagnostics snapshot. Reuses `FanCard`, the Disk health cards and the
/// diagnostics card verbatim rather than re-deriving any of them.
struct SensorsView: View {
    @EnvironmentObject private var model: VitalsModel

    var body: some View {
        MetricScroll {
            TemperaturesCard()
            FanCard()
            if let disk = model.diskHealth {
                DiskHealthHeroCard(disk: disk)
                DiskEnduranceCard(disk: disk)
                DiskLifetimeCard(disk: disk)
            }
            HealthDiagnosticsCard()
        }
    }
}

/// Every temperature Vitals can read, gathered: the CPU average/hottest and macOS
/// thermal state up top, the other hardware areas (GPU, SSD, battery) as rows, and
/// the per-core die grid below. Honest about gaps — an area with no sensor simply
/// isn't listed, never shown as a fabricated 0°.
private struct TemperaturesCard: View {
    @EnvironmentObject private var model: VitalsModel
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        SectionCard(title: "Temperatures", symbol: "thermometer.medium") {
            if model.cpuSensors.isEmpty && model.gpuTemp == nil
                && model.ssdTemp == nil && model.batteryTemp == nil {
                Text("Temperature sensors are unavailable on this Mac.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 24) {
                        statColumn("Average", model.averageCPUTemp.map { settings.format($0) } ?? "—")
                        statColumn("Hottest", model.hottestCPUSensor.map { settings.format($0.celsius) } ?? "—",
                                   note: model.hottestCPUSensor?.label)
                        statColumn("Thermal", model.thermalState.label)
                        Spacer(minLength: 0)
                    }
                    let others = otherTemps
                    if !others.isEmpty {
                        Divider()
                        MetricRowGrid(rows: others)
                    }
                    if !model.cpuSensors.isEmpty {
                        Divider()
                        CoreTempGrid(sensors: model.cpuSensors)
                    }
                }
            }
        }
    }

    /// Temperatures outside the CPU die — only the ones this Mac actually reports.
    private var otherTemps: [MetricRow] {
        var rows: [MetricRow] = []
        if let gpu = model.gpuTemp {
            rows.append(MetricRow(symbol: "cpu.fill", label: "GPU", value: settings.formatWithUnit(gpu)))
        }
        if let ssd = model.ssdTemp {
            rows.append(MetricRow(symbol: "internaldrive", label: "SSD", value: settings.formatWithUnit(ssd)))
        }
        if let battery = model.batteryTemp {
            rows.append(MetricRow(symbol: "battery.100percent", label: "Battery", value: settings.formatWithUnit(battery)))
        }
        return rows
    }
}
