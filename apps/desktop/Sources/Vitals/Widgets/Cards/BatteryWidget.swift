import SwiftUI

/// Battery charge at a glance: percent, time remaining, a capacity bar, and
/// the charge-state line — the same real `BatterySnapshot` the Battery tab
/// reads, through the same shared `BatteryContent` wording/tint rules. On a
/// Mac with no battery it says so; it never invents a number.
struct BatteryWidget: View {
    @EnvironmentObject private var model: VitalsModel
    @Environment(\.widgetScale) private var scale

    var body: some View {
        let battery = model.battery
        let tint = battery.map(BatteryContent.chargeTint(for:)) ?? .green
        WidgetCard(title: "Battery", symbol: BatteryContent.symbol(for: battery), tint: tint,
                   intensity: intensity(battery)) {
            if let battery {
                HStack(alignment: .firstTextBaseline, spacing: 6 * scale) {
                    Text("\(Int(battery.percent))%")
                        .scaledFont(24, weight: .semibold, design: .rounded)
                        .monospacedDigit()
                        .numericTransition()
                    Spacer(minLength: 0)
                    if let minutes = battery.timeRemainingMinutes {
                        Text(BatteryContent.timeText(minutes))
                            .scaledFont(10.5)
                            .monospacedDigit()
                            .foregroundStyle(tint)
                    }
                }
                capacityBar(battery.percent / 100, tint: tint)
                Text(BatteryContent.stateLine(for: battery))
                    .scaledFont(10.5)
                    .foregroundStyle(.tertiary)
            } else {
                Text("—")
                    .scaledFont(24, weight: .semibold, design: .rounded)
                Text("No battery")
                    .scaledFont(10.5)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    /// Rim severity: a draining battery warms the rim as it empties; on
    /// external power there's nothing to worry about.
    private func intensity(_ battery: BatterySnapshot?) -> Double {
        guard let battery, !battery.externalPower else { return 0 }
        return 1 - battery.percent / 100
    }

    private func capacityBar(_ fraction: Double, tint: Color) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary.opacity(0.5))
                Capsule().fill(tint)
                    .frame(width: max(0, min(1, fraction)) * geo.size.width)
            }
        }
        .frame(height: 5 * scale)
    }
}
