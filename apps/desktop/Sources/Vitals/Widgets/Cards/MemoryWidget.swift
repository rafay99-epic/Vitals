import SwiftUI

/// Memory used (GB and %), tinted by macOS memory pressure, with a usage
/// sparkline.
struct MemoryWidget: View {
    @EnvironmentObject private var model: VitalsModel

    var body: some View {
        let memory = model.memory
        let tint = memory.map { pressureColor($0.pressure) } ?? .indigo
        WidgetCard(title: "Memory", symbol: "memorychip", tint: tint,
                   intensity: memory?.usedFraction ?? 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(memory.map { String(format: "%.1f GB", gigabytes($0.used)) } ?? "—")
                    .font(.system(size: 27, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Spacer(minLength: 0)
                if let memory {
                    Text("\(Int((memory.usedFraction * 100).rounded()))%")
                        .font(.caption2)
                        .foregroundStyle(tint)
                }
            }
            WidgetSparkline(values: model.chartHistory.suffix(40).map(\.memoryUsed), tint: tint)
                .frame(height: 22)
        }
    }
}
