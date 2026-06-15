import SwiftUI

/// The Health tab: one honest "is my Mac struggling right now?" answer, tying
/// together signals shown separately elsewhere — macOS's thermal state (its own
/// throttling signal), memory pressure, the hottest CPU sensor, fan speed and
/// SoC power. Every factor points back at a real reading; the verdict is just
/// the worst of them, never a fabricated score.
struct HealthView: View {
    @EnvironmentObject private var model: VitalsModel
    @EnvironmentObject private var settings: AppSettings

    private var factors: [HealthFactor] {
        var list: [HealthFactor] = []

        list.append(HealthFactor(
            level: SystemHealth.thermalLevel(model.thermalState),
            symbol: "thermometer.medium",
            title: "Thermal state",
            detail: throttling
                ? "\(model.thermalState.label) · macOS is limiting performance to cool down"
                : "\(model.thermalState.label) · reported by macOS"
        ))

        if let hottest = model.hottestCPUSensor {
            list.append(HealthFactor(
                level: SystemHealth.temperatureLevel(celsius: hottest.celsius),
                symbol: "cpu",
                title: "CPU temperature",
                detail: "Hottest \(settings.formatWithUnit(hottest.celsius)) · \(hottest.label)"
            ))
        }

        if let memory = model.memory {
            var detail = "\(memory.pressure.label) pressure"
            if memory.swapUsed > 0 {
                detail += String(format: " · %.2f GB swap", gigabytes(memory.swapUsed))
            }
            list.append(HealthFactor(
                level: SystemHealth.pressureLevel(memory.pressure),
                symbol: "memorychip",
                title: "Memory",
                detail: detail
            ))
        }

        if !model.fans.isEmpty {
            let level = model.fans
                .map { SystemHealth.fanLevel(rpm: $0.rpm, maxRPM: $0.maxRPM) }
                .max() ?? .good
            let rpm = model.fans.map(\.rpm).max() ?? 0
            list.append(HealthFactor(
                level: level,
                symbol: "fan",
                title: "Cooling",
                detail: level == .elevated
                    ? "Fans near full · \(Int(rpm)) rpm"
                    : "\(Int(rpm)) rpm"
            ))
        }

        return list
    }

    private var throttling: Bool {
        SystemHealth.isThrottling(model.thermalState)
    }

    var body: some View {
        // Build the signals once per render — `overall` is just their worst.
        let factors = self.factors
        let overall = factors.map(\.level).max() ?? .good
        return MetricScroll {
            HealthHeroCard(level: overall, throttling: throttling)
            HealthFactorsCard(factors: factors)
            if let power = model.power {
                HealthPowerCard(power: power)
            }
            HealthDiagnosticsCard()
        }
    }
}

private struct HealthFactor: Identifiable {
    let level: SystemHealth.Level
    let symbol: String
    let title: String
    let detail: String
    var id: String { title }
}

// MARK: - Verdict hero

private struct HealthHeroCard: View {
    let level: SystemHealth.Level
    let throttling: Bool

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().fill(level.tint.opacity(0.16)).frame(width: 64, height: 64)
                Image(systemName: throttling ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 28, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(level.tint)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(SystemHealth.headline(level: level, throttling: throttling))
                    .font(.system(size: 22, weight: .semibold))
                Text(throttling
                     ? "macOS has lowered clocks to protect the machine. Quitting heavy apps will bring it back — check Processes."
                     : "Vitals is watching temperature, memory pressure and cooling. Nothing needs attention right now.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .cardBackground()
    }
}

// MARK: - Factor rows

private struct HealthFactorsCard: View {
    let factors: [HealthFactor]

    var body: some View {
        SectionCard(title: "Signals", symbol: "list.bullet") {
            VStack(spacing: 12) {
                ForEach(factors) { factor in
                    HStack(spacing: 12) {
                        Image(systemName: factor.symbol)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(factor.level.tint)
                            .frame(width: 28, height: 28)
                            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(factor.level.tint.opacity(0.14)))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(factor.title).font(.callout.weight(.medium))
                            Text(factor.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Circle().fill(factor.level.tint).frame(width: 9, height: 9)
                    }
                    if factor.id != factors.last?.id { Divider() }
                }
            }
        }
    }
}

// MARK: - SoC power

private struct HealthPowerCard: View {
    let power: PowerSnapshot

    var body: some View {
        SectionCard(title: "SoC power", symbol: "bolt.fill") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    PowerTile(title: "CPU", watts: power.cpuWatts, symbol: "cpu", tint: .blue)
                    PowerTile(title: "GPU", watts: power.gpuWatts, symbol: "cpu.fill", tint: .purple)
                    PowerTile(title: "Neural Engine", watts: power.aneWatts, symbol: "brain", tint: .pink)
                }
                HStack {
                    Text("Total package").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Text(wattsText(power.total))
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                        .numericTransition()
                }
            }
        }
    }
}

// MARK: - Diagnostics

private struct HealthDiagnosticsCard: View {
    @EnvironmentObject private var model: VitalsModel
    @EnvironmentObject private var settings: AppSettings
    @State private var copied = false

    var body: some View {
        SectionCard(title: "Diagnostics", symbol: "doc.on.clipboard") {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Copy a snapshot of every current reading")
                        .font(.callout)
                    Text("Plain text — handy to paste into a support thread or note.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    DiagnosticSnapshot.copyToPasteboard(model: model, settings: settings)
                    copied = true
                    Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.clipboard")
                }
                .controlSize(.small)
            }
        }
    }
}
