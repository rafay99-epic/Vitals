import SwiftUI

/// Fan speed — honest about a stopped or absent fan (0 rpm / Fanless / no SMC).
struct FanWidget: View {
    @EnvironmentObject private var model: VitalsModel

    var body: some View {
        WidgetCard(title: "Fan", symbol: "fan", tint: .cyan) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                if model.hasSMC, model.fans.first != nil {
                    Text("rpm")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var value: String {
        guard model.hasSMC else { return "—" }
        guard let fan = model.fans.first else { return "Fanless" }
        return "\(Int(fan.rpm))"
    }

    private var subtitle: String {
        guard model.hasSMC else { return "No fan sensor" }
        guard let fan = model.fans.first else { return "No fan on this Mac" }
        return model.fans.count > 1 ? "\(model.fans.count) fans" : "max \(Int(fan.maxRPM)) rpm"
    }
}
