import SwiftUI
import Charts

/// The Battery tab: the full health picture System Settings keeps hidden —
/// real capacity against design, cycle count, condition, the charge trend over
/// time, the live USB-C / MagSafe adapter negotiation, and voltage / current /
/// power / temperature straight from the pack's own gauge. Every figure is a
/// direct AppleSmartBattery reading; a machine with no battery says so rather
/// than showing zeros.
struct BatteryView: View {
    @EnvironmentObject private var model: VitalsModel
    /// True only while the Battery tab is visible — gates the history chart so it
    /// doesn't rebuild marks every tick while mounted in the background (mirrors GPUView).
    let isActive: Bool

    var body: some View {
        MetricScroll {
            if let battery = model.battery {
                BatteryHeroCard(battery: battery)
                if let adapter = battery.adapter {
                    BatteryAdapterCard(adapter: adapter)
                }
                // Gate the scan on isActive too (mirrors GPUView) so a backgrounded
                // mounted tab doesn't walk chartHistory every tick.
                if isActive, model.chartHistory.contains(where: { $0.batteryPercent != nil }) {
                    BatteryHistoryCard()
                }
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
                    Text(BatteryContent.stateLine(for: battery)).font(.title3).foregroundStyle(.secondary)
                    Spacer()
                    if let minutes = battery.timeRemainingMinutes {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(BatteryContent.timeText(minutes)).font(.headline).monospacedDigit()
                            Text(battery.externalPower ? "until full" : "remaining")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Gauge(value: battery.percent / 100) { EmptyView() }
                    .gaugeStyle(.accessoryLinearCapacity)
                    .tint(BatteryContent.chargeTint(for: battery))
            }
        }
    }
}

// MARK: - Power adapter (USB-C PD / MagSafe)

private struct BatteryAdapterCard: View {
    let adapter: AdapterInfo

    var body: some View {
        SectionCard(title: "Power adapter", symbol: "powerplug.fill") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(heroValue)
                        .font(.system(size: 32, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .numericTransition()
                    Text(adapter.deliveredWatts != nil ? "delivering" : "rated")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let name = adapter.name {
                        Label(name, systemImage: adapter.isWireless ? "wave.3.right" : "powerplug")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else if adapter.isWireless {
                        Label("Wireless", systemImage: "wave.3.right")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                if !rows.isEmpty {
                    Divider()
                    MetricRowGrid(rows: rows)
                }
            }
        }
    }

    /// The live delivered watts when the charger reports them — even ~0 W when
    /// the battery is full (honest, like a stopped fan reading 0 rpm), so the
    /// "delivering" label always matches the number. Falls back to the rated
    /// figure (labelled "rated"), then "Connected". Never a fabricated number.
    private var heroValue: String {
        if let delivered = adapter.deliveredWatts {
            return String(format: "%.1f W", delivered)
        }
        if let watts = adapter.watts { return "\(watts) W" }
        return "Connected"
    }

    private var rows: [MetricRow] {
        var rows: [MetricRow] = []
        // Show the rated cap alongside the live draw — they diverge as the battery fills.
        if adapter.deliveredWatts != nil, let watts = adapter.watts {
            rows.append(MetricRow(symbol: "bolt.fill", label: "Rated power", value: "\(watts) W"))
        }
        if let voltage = adapter.voltage {
            rows.append(MetricRow(symbol: "waveform", label: "Voltage", value: String(format: "%.1f V", voltage)))
        }
        if let amperage = adapter.amperage {
            rows.append(MetricRow(symbol: "arrow.left.arrow.right", label: "Current", value: String(format: "%.2f A", amperage)))
        }
        return rows
    }
}

// MARK: - Charge history

private struct BatteryHistoryCard: View {
    @EnvironmentObject private var model: VitalsModel

    var body: some View {
        SectionCard(title: "Charge history", symbol: "chart.xyaxis.line") {
            // Only inserted by BatteryView while the tab is active, so the chart
            // never rebuilds marks in the background (see GPUView). Deferred keeps
            // the 50–150 ms first-layout cost off the tab-switch animation.
            Deferred { chart }.frame(height: 150)
        }
    }

    private var chart: some View {
        Chart(model.chartHistory) { sample in
            if let percent = sample.batteryPercent {
                AreaMark(x: .value("Time", sample.time), y: .value("Charge", percent))
                    .foregroundStyle(LinearGradient(colors: [.green.opacity(0.35), .green.opacity(0.02)],
                                                    startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("Time", sample.time), y: .value("Charge", percent))
                    .foregroundStyle(.green)
                    .interpolationMethod(.catmullRom)
            }
        }
        .chartYScale(domain: 0...100)
        .chartYAxisLabel("%")
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
