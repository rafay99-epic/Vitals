import SwiftUI

/// Average CPU die temperature, tinted by the same gradient the dashboard uses,
/// with a temperature sparkline. Reads the shared `VitalsModel`.
struct CPUWidget: View {
    @EnvironmentObject private var model: VitalsModel
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        let tint = model.averageCPUTemp.map(tempGradientColor) ?? .secondary
        WidgetCard(title: "CPU", symbol: "cpu", tint: tint,
                   intensity: model.averageCPUTemp.map(tempSeverity) ?? 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(model.averageCPUTemp.map { settings.format($0, decimals: 0) } ?? "—")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(tint)
                Spacer(minLength: 0)
                Text("\(HardwareInfo.coreCount) cores")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            WidgetSparkline(values: model.chartHistory.suffix(40).map(\.averageCPU), tint: tint)
                .frame(height: 22)
        }
    }
}
