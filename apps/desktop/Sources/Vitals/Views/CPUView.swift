import SwiftUI

/// The CPU tab: a deeper look than the Dashboard's summary card. It splits the
/// blended load into Performance vs Efficiency clusters, shows which *specific*
/// cores are working (per-core utilisation), the per-core die temperatures, and
/// the CPU power rail. Everything cluster-aware degrades to the honest blended
/// view when there's no trusted P/E split (Intel, a VM) — no fabricated labels.
struct CPUView: View {
    @EnvironmentObject private var model: VitalsModel

    var body: some View {
        MetricScroll {
            CPUHeroCard()
            if model.cpuClusters != nil || !model.cpuPerCore.isEmpty {
                CPUCoresCard()
            }
            CPUThermalPowerCard()
        }
    }
}

// MARK: - Hero

private struct CPUHeroCard: View {
    @EnvironmentObject private var model: VitalsModel

    var body: some View {
        SectionCard(title: "CPU", symbol: "cpu") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(String(format: "%.0f%%", model.cpuUsage))
                        .font(.system(size: 40, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .numericTransition()
                    Text("load")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(HardwareInfo.chipName).font(.headline)
                        Text(coreSummary).font(.callout).foregroundStyle(.secondary)
                    }
                }
                utilizationBar(fraction: model.cpuUsage / 100, tint: .blue)
            }
        }
    }

    /// "4 Performance · 6 Efficiency" when the split is trusted, otherwise the
    /// honest total logical-core count.
    private var coreSummary: String {
        let performance = model.cpuPerCore.filter(\.isPerformance).count
        let efficiency = model.cpuPerCore.count - performance
        if performance > 0 && efficiency > 0 {
            return "\(performance) Performance · \(efficiency) Efficiency"
        }
        return "\(HardwareInfo.coreCount) cores"
    }
}

// MARK: - Clusters + per-core utilisation

private struct CPUCoresCard: View {
    @EnvironmentObject private var model: VitalsModel

    var body: some View {
        SectionCard(title: "Cores", symbol: "square.split.1x2") {
            VStack(alignment: .leading, spacing: 14) {
                if let clusters = model.cpuClusters {
                    VStack(alignment: .leading, spacing: 7) {
                        ClusterMeter(label: "Performance", percent: clusters.performance, tint: .accentColor)
                        ClusterMeter(label: "Efficiency", percent: clusters.efficiency, tint: .teal)
                    }
                }

                let performance = model.cpuPerCore.filter(\.isPerformance)
                let efficiency = model.cpuPerCore.filter { !$0.isPerformance }
                if !performance.isEmpty || !efficiency.isEmpty {
                    Divider()
                    coreGroup("Performance cores", performance, prefix: "P", tint: .accentColor)
                    coreGroup("Efficiency cores", efficiency, prefix: "E", tint: .teal)
                }
            }
        }
    }

    @ViewBuilder
    private func coreGroup(_ title: String, _ cores: [CoreUsage], prefix: String, tint: Color) -> some View {
        if !cores.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                ForEach(Array(cores.enumerated()), id: \.element.id) { index, core in
                    ClusterMeter(label: "\(prefix)\(index)", percent: core.percent, tint: tint)
                }
            }
        }
    }
}

// MARK: - Temperature + CPU power rail

private struct CPUThermalPowerCard: View {
    @EnvironmentObject private var model: VitalsModel
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        SectionCard(title: "Temperature", symbol: "thermometer.medium") {
            if model.cpuSensors.isEmpty {
                Text("Per-core temperatures unavailable on this Mac.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 24) {
                        stat("Average", model.averageCPUTemp.map { settings.format($0) } ?? "—")
                        stat("Hottest", model.hottestCPUSensor.map { settings.format($0.celsius) } ?? "—",
                             note: model.hottestCPUSensor?.label)
                        if let power = model.power {
                            stat("CPU power", wattsText(power.cpuWatts))
                        }
                        Spacer(minLength: 0)
                    }
                    Divider()
                    CoreTempGrid(sensors: model.cpuSensors)
                }
            }
        }
    }

    private func stat(_ label: String, _ value: String, note: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .numericTransition()
            if let note {
                Text(note).font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }
}
