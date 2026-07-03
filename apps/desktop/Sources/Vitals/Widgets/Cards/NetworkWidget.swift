import SwiftUI

/// Live network throughput with a download-rate sparkline. Mirrors `GPUWidget`.
struct NetworkWidget: View {
    @EnvironmentObject private var model: VitalsModel
    @Environment(\.widgetScale) private var scale

    var body: some View {
        WidgetCard(title: "Network", symbol: "arrow.up.arrow.down", tint: .mint) {
            HStack(alignment: .firstTextBaseline, spacing: 6 * scale) {
                Text(model.network.map { byteRateText($0.downBps) } ?? "—")
                    .scaledFont(30, weight: .semibold, design: .rounded)
                    .monospacedDigit()
                    .numericTransition()
                Spacer(minLength: 0)
                Text(detail)
                    .scaledFont(10.5)
                    .foregroundStyle(.secondary)
            }
            WidgetSparkline(values: model.chartHistory.suffix(40).compactMap(\.downBps), tint: .mint)
                .frame(maxHeight: .infinity)
                .frame(minHeight: 22 * scale)
        }
    }

    /// Upload rate — the hero number already carries download, the primary reading.
    private var detail: String {
        guard let network = model.network else { return "" }
        return "↑ \(byteRateText(network.upBps))"
    }
}
