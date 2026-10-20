import SwiftUI

/// Top CPU consumers, as bare content for a card to wrap.
struct TopProcessesContent: View {
    @Environment(VitalsModel.self) private var model

    var body: some View {
        if model.topProcesses.isEmpty {
            CardPlaceholder("Gathering…", minHeight: 120)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(model.topProcesses) { process in
                    HStack {
                        Text(process.name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text(String(format: "%.1f%%", process.cpuPercent))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
                Text("CPU per process · 100% = one core")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

/// Every fan's live speed and mode, read-only. Fanless Macs say so.
struct FanCard: View {
    @Environment(VitalsModel.self) private var model

    var body: some View {
        SectionCard(title: "Fans", symbol: "fan") {
            if model.fans.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: model.hasSMC ? "fan.slash" : "questionmark.circle")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text(model.hasSMC ? "This Mac is fanless. It cools passively." : "Fan data unavailable.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(model.fans) { fan in
                        fanRow(fan)
                        if fan.id != model.fans.last?.id {
                            Divider()
                        }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
            }
        }
    }

    private func fanRow(_ fan: SMC.Fan) -> some View {
        HStack(spacing: 16) {
            Gauge(value: gaugeValue(fan), in: 0...1) {
                EmptyView()
            } currentValueLabel: {
                Image(systemName: "fan")
                    .font(.caption)
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(.cyan)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(Int(fan.rpm)) rpm")
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .numericTransition()
                if let manual = fan.isManual {
                    Text(manual ? "Manual · target \(Int(fan.targetRPM)) rpm" : "Automatic")
                        .font(.caption)
                        .foregroundStyle(manual ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                }
                Text("Range \(Int(fan.minRPM))–\(Int(fan.maxRPM)) rpm")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
    }

    private func gaugeValue(_ fan: SMC.Fan) -> Double {
        guard fan.maxRPM > 0 else { return 0 }
        return min(max(fan.rpm / fan.maxRPM, 0), 1)
    }
}

enum BatteryContent {
    /// Charge-state SF Symbol.
    static func symbol(for battery: BatterySnapshot?) -> String {
        guard let battery else { return "battery.100percent" }
        if battery.isCharging { return "battery.100percent.bolt" }
        switch battery.percent {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    // Shared wording, tint, and clock format for every battery surface.

    /// "Charging" / "On power adapter" / "On battery": the charge-state line.
    static func stateLine(for battery: BatterySnapshot) -> String {
        if battery.isCharging { return "Charging" }
        if battery.externalPower { return battery.fullyCharged ? "Fully charged, on power adapter" : "On power adapter" }
        return "On battery"
    }

    /// Green when charging or healthy, orange under 50%, red under 20%.
    static func chargeTint(for battery: BatterySnapshot) -> Color {
        if battery.isCharging { return .green }
        switch battery.percent {
        case ..<20: return .red
        case ..<50: return .orange
        default: return .green
        }
    }

    /// "42 min" / "3 h 12 min".
    static func timeText(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes) min" : "\(minutes / 60) h \(minutes % 60) min"
    }
}

/// SoC power on the Overview: package total plus the CPU / GPU / Neural Engine
/// rails. Shows a note until the first energy delta lands (or when IOReport is
/// unavailable), never a fake 0 W.
struct PowerCard: View {
    @Environment(VitalsModel.self) private var model

    var body: some View {
        SectionCard(title: "Power", symbol: "bolt.fill") {
            if let power = model.power {
                PowerRails(power: power)
            } else {
                Text("Power readings appear in a moment — or aren't available on this Mac.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            }
        }
    }
}
