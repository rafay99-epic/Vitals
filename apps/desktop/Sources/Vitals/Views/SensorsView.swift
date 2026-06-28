import SwiftUI

/// The Temps & Fans section: the hardware long-tail in one place (TG Pro's
/// pattern) — every temperature, the fans and their control, and the internal
/// drive's SMART health — plus a one-click diagnostics snapshot. Reuses
/// `FanCard`, the Disk health cards and the diagnostics card verbatim rather
/// than re-deriving any of them.
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
