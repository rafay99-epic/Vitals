import SwiftUI

/// The Battery tab: the full health picture System Settings keeps hidden —
/// real capacity against design, cycle count, condition, and live voltage /
/// current / power / temperature straight from the pack's own gauge. Every
/// figure is a direct AppleSmartBattery reading; a machine with no battery says
/// so rather than showing zeros.
struct BatteryView: View {
    @EnvironmentObject private var model: VitalsModel

    var body: some View {
        MetricScroll {
            if let battery = model.battery {
                BatteryHeroCard(battery: battery)
                BatteryHealthCard(battery: battery)
                BatteryDetailCard(battery: battery)
            } else {
                EmptyStateView(
                    symbol: "bolt.slash",
                    tint: .green,
                    title: "No battery",
                    message: "This Mac runs on wall power — there's no battery to report on. Charge, health and power figures appear here on a notebook."
                ) { EmptyView() }
            }
        }
    }
}

// MARK: - Charge hero

private struct BatteryHeroCard: View {
    let battery: BatterySnapshot

    var body: some View {
        SectionCard(title: "Charge", symbol: BatteryContent.symbol(for: battery)) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(Int(battery.percent))%")
                        .font(.system(size: 40, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .numericTransition()
                    Text(stateLine).font(.title3).foregroundStyle(.secondary)
                    Spacer()
                    if let minutes = battery.timeRemainingMinutes {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(timeText(minutes)).font(.headline).monospacedDigit()
                            Text(battery.externalPower ? "until full" : "remaining")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Gauge(value: battery.percent / 100) { EmptyView() }
                    .gaugeStyle(.accessoryLinearCapacity)
                    .tint(chargeTint)
            }
        }
    }

    private var stateLine: String {
        if battery.isCharging { return "Charging" }
        if battery.externalPower { return battery.fullyCharged ? "Fully charged, on power adapter" : "On power adapter" }
        return "On battery"
    }

    private var chargeTint: Color {
        if battery.isCharging { return .green }
        switch battery.percent {
        case ..<20: return .red
        case ..<50: return .orange
        default: return .green
        }
    }

    private func timeText(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes) min" : "\(minutes / 60) h \(minutes % 60) min"
    }
}

// MARK: - Health

private struct BatteryHealthCard: View {
    let battery: BatterySnapshot

    var body: some View {
        SectionCard(title: "Health", symbol: "heart.fill") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(battery.healthPercent.map { String(format: "%.0f%%", $0) } ?? "—")
                        .font(.system(size: 32, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .numericTransition()
                    Text("maximum capacity").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    conditionBadge
                }
                if let health = battery.healthPercent {
                    Gauge(value: min(health / 100, 1)) { EmptyView() }
                        .gaugeStyle(.accessoryLinearCapacity)
                        .tint(healthTint(health))
                }
                Divider()
                MetricRowGrid(rows: rows)
            }
        }
    }

    private var rows: [MetricRow] {
        var rows: [MetricRow] = []
        if let cycles = battery.cycleCount {
            rows.append(MetricRow(symbol: "arrow.triangle.2.circlepath", label: "Cycle count", value: "\(cycles)"))
        }
        if let max = battery.maxCapacity, let design = battery.designCapacity {
            rows.append(MetricRow(symbol: "battery.100percent", label: "Full charge", value: "\(max) mAh"))
            rows.append(MetricRow(symbol: "ruler", label: "Design capacity", value: "\(design) mAh"))
        }
        rows.append(MetricRow(symbol: "checkmark.seal", label: "Condition", value: battery.condition))
        return rows
    }

    private var conditionBadge: some View {
        let ok = battery.condition == "Normal"
        return Text(battery.condition)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill((ok ? Color.green : .orange).opacity(0.18)))
            .foregroundStyle(ok ? Color.green : .orange)
    }

    private func healthTint(_ health: Double) -> Color {
        switch health {
        case ..<80: return .orange
        default: return .green
        }
    }
}

// MARK: - Live electrical detail

private struct BatteryDetailCard: View {
    @EnvironmentObject private var model: VitalsModel
    @EnvironmentObject private var settings: AppSettings
    let battery: BatterySnapshot

    var body: some View {
        SectionCard(title: "Power", symbol: "bolt.fill") {
            MetricRowGrid(rows: rows)
        }
    }

    private var rows: [MetricRow] {
        var rows: [MetricRow] = []
        if let watts = battery.watts, abs(watts) > 0.05 {
            rows.append(MetricRow(
                symbol: watts > 0 ? "bolt.fill" : "bolt",
                label: watts > 0 ? "Charging" : "Discharging",
                value: String(format: "%.1f W", abs(watts))
            ))
        }
        if let voltage = battery.voltage {
            rows.append(MetricRow(symbol: "waveform", label: "Voltage", value: String(format: "%.2f V", voltage)))
        }
        if let amperage = battery.amperage {
            rows.append(MetricRow(symbol: "arrow.left.arrow.right", label: "Current", value: String(format: "%.2f A", amperage)))
        }
        // The pack's own gauge is more specific than the shared HID die sensor.
        if let temp = battery.temperature ?? model.batteryTemp {
            rows.append(MetricRow(symbol: "thermometer.medium", label: "Temperature", value: settings.formatWithUnit(temp)))
        }
        return rows
    }
}

// MARK: - Shared key/value grid

struct MetricRow: Identifiable {
    let symbol: String
    let label: String
    let value: String
    var id: String { label }
}

/// A two-column key/value grid in the card language — fixed columns (never
/// `.adaptive`, per the performance rules) so it doesn't reflow mid-animation.
struct MetricRowGrid: View {
    let rows: [MetricRow]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading),
                            GridItem(.flexible(), alignment: .leading)],
                  spacing: 10) {
            ForEach(rows) { row in
                HStack(spacing: 8) {
                    Image(systemName: row.symbol)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 18)
                    Text(row.label).font(.callout).foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(row.value)
                        .font(.system(.callout, design: .rounded, weight: .medium))
                        .monospacedDigit()
                        .numericTransition()
                }
            }
        }
    }
}
