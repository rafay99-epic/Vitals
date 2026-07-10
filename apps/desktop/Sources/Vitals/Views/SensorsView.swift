import SwiftUI

/// The Temps & Fans section: the thermal hardware in one place (TG Pro's
/// pattern) — every temperature (the SSD's included, in the Temperatures card),
/// the fans and their control — plus a one-click diagnostics snapshot. The SSD's
/// *health* (wear, endurance, TRIM, lifetime) lives in Storage, next to disk
/// space; only the drive temperature belongs here. Reuses `FanCard` and the
/// diagnostics card verbatim rather than re-deriving them.
struct SensorsView: View {
    var body: some View {
        MetricScroll {
            TemperaturesCard()
            FanCard()
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
            if model.hasLoaded && model.cpuSensors.isEmpty && model.gpuTemp == nil
                && model.ssdTemp == nil && model.batteryTemp == nil {
                // Only after the first sample — before it, the rows below show
                // "—" rather than a false "unavailable" flash on first mount.
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
