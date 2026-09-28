import SwiftUI

/// The Temps & Fans section: every temperature Vitals can read, plus the fans.
/// SSD *health* lives in Disk Health; only the drive temperature belongs here.
struct SensorsView: View {
    var body: some View {
        MetricScroll {
            TemperaturesCard()
            FanCard()
        }
    }
}

/// Every readable temperature: CPU average/hottest and thermal state, other
/// areas (GPU, SSD, battery) as rows, then the per-core grid. An area with no
/// sensor isn't listed rather than shown as 0°.
private struct TemperaturesCard: View {
    @Environment(VitalsModel.self) private var model
    @Environment(AppSettings.self) private var settings

    var body: some View {
        SectionCard(title: "Temperatures", symbol: "thermometer.medium") {
            if model.hasLoaded && model.cpuSensors.isEmpty && model.gpuTemp == nil
                && model.ssdTemp == nil && model.batteryTemp == nil {
                // Only after the first sample, so first mount doesn't flash "unavailable".
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

    /// Temperatures outside the CPU die, only the ones this Mac actually reports.
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
