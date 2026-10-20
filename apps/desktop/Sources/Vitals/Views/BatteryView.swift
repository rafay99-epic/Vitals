import SwiftUI
import Charts

/// The Battery section: capacity vs design, cycles, condition, charge trend,
/// adapter negotiation, and the pack's electrical readings (AppleSmartBattery).
struct BatteryView: View {
    @Environment(VitalsModel.self) private var model

    var body: some View {
        MetricScroll {
            if let battery = model.battery {
                BatteryHeroCard(battery: battery)
                if let adapter = battery.adapter {
                    BatteryAdapterCard(adapter: adapter)
                }
                if model.chartHistory.hasReading(\.batteryPercent) {
                    BatteryHistoryCard()
                }
                BatteryHealthCard(battery: battery)
                BatteryDetailCard(battery: battery)
            } else {
                EmptyStateView(
                    symbol: "bolt.slash",
                    tint: .green,
                    title: "No battery",
                    message: "This Mac runs on wall power — there's no battery to report on. Charge, health and power figures appear here on a notebook. Sleep blockers are listed below regardless."
                )
            }
            // Power draw and sleep blockers matter on wall power too, so they
            // sit outside the battery gate.
            if model.chartHistory.hasReading(\.totalWatts) {
                BatteryPowerDrawCard()
            }
            SleepBlockersCard()
        }
    }
}

// MARK: - Charge hero

private struct BatteryHeroCard: View {
    let battery: BatterySnapshot

    var body: some View {
        SectionCard(title: "Charge", symbol: BatteryContent.symbol(for: battery)) {
            VStack(alignment: .leading, spacing: 12) {
                HeroReadout(value: "\(Int(battery.percent))%", caption: BatteryContent.stateLine(for: battery), large: true) {
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
                HeroReadout(value: heroValue, caption: adapter.deliveredWatts != nil ? "delivering" : "rated") {
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

    /// Live delivered watts when the charger reports them (even ~0 W when full, so
    /// "delivering" matches the number), else the rated figure, else "Connected".
    private var heroValue: String {
        if let delivered = adapter.deliveredWatts {
            return String(format: "%.1f W", delivered)
        }
        if let watts = adapter.watts { return "\(watts) W" }
        return "Connected"
    }

    private var rows: [MetricRow] {
        var rows: [MetricRow] = []
        // Show the rated cap alongside the live draw; they diverge as the battery fills.
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
    @Environment(VitalsModel.self) private var model

    var body: some View {
        SectionCard(title: "Charge history", symbol: "chart.xyaxis.line") {
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
                HeroReadout(
                    value: battery.healthPercent.map { String(format: "%.0f%%", $0) } ?? "—",
                    caption: "maximum capacity"
                ) {
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
            .capsuleTag(ok ? .green : .orange)
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
    @Environment(VitalsModel.self) private var model
    @Environment(AppSettings.self) private var settings
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

// MARK: - Power draw over time

private struct BatteryPowerDrawCard: View {
    @Environment(VitalsModel.self) private var model

    var body: some View {
        SectionCard(title: "Power draw", symbol: "bolt.fill") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Total system-on-chip package power — the live pull on the battery or adapter.")
                    .font(.caption).foregroundStyle(.secondary)
                Deferred { chart }.frame(height: 150)
            }
        }
    }

    private var chart: some View {
        Chart(model.chartHistory) { sample in
            if let watts = sample.totalWatts {
                AreaMark(x: .value("Time", sample.time), y: .value("Watts", watts))
                    .foregroundStyle(LinearGradient(colors: [.orange.opacity(0.32), .orange.opacity(0.02)],
                                                    startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("Time", sample.time), y: .value("Watts", watts))
                    .foregroundStyle(.orange)
                    .interpolationMethod(.catmullRom)
            }
        }
        .chartYAxisLabel("W")
    }
}

// MARK: - Sleep & wake (power assertions)

/// Apps holding a sleep assertion, re-read every 5 s while mounted.
private struct SleepBlockersCard: View {
    @State private var model = SleepBlockersModel()

    var body: some View {
        SectionCard(title: "Sleep & wake", symbol: "moon.zzz.fill") {
            if let blockers = model.blockers {
                if blockers.isEmpty {
                    // Scoped to the user's apps: a system daemon holding an
                    // assertion isn't listed, so don't promise the Mac will sleep.
                    Label("No apps are keeping your Mac awake.", systemImage: "checkmark.circle.fill")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(blockers) { app in
                            HStack(spacing: 10) {
                                AppIcon(bundleURL: app.bundleURL)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(app.name).font(.callout).lineLimit(1)
                                    if let reason = app.reason, !reason.isEmpty {
                                        Text(reason).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                                Spacer(minLength: 8)
                                Text(app.preventsSystemSleep ? "System" : "Display")
                                    .font(.caption.weight(.medium))
                                    .capsuleTag(.orange)
                            }
                        }
                    }
                }
            } else {
                HStack { ProgressView().controlSize(.small); Text("Checking…").font(.callout).foregroundStyle(.secondary) }
            }
        }
        .task { await model.watch() }
    }
}

private struct AppIcon: View {
    let bundleURL: URL?

    var body: some View {
        if let bundleURL {
            AppIconView(url: bundleURL, size: 26)
        } else {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.secondary.opacity(0.14))
                .frame(width: 26, height: 26)
                .overlay(Image(systemName: "gearshape.fill").font(.system(size: 12)).foregroundStyle(.secondary))
        }
    }
}
