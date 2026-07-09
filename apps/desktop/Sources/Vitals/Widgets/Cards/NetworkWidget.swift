import SwiftUI

/// Live network throughput: the summed download / upload rates with a
/// download-trend sparkline. Reads the shared `VitalsModel` — both rates show
/// "—" until the second sample lands (a rate needs two readings).
struct NetworkWidget: View {
    @EnvironmentObject private var model: VitalsModel
    @Environment(\.widgetScale) private var scale

    var body: some View {
        WidgetCard(title: "Network", symbol: "network", tint: .mint) {
            HStack(alignment: .firstTextBaseline, spacing: 12 * scale) {
                rate("arrow.down", model.network?.totalInPerSec, tint: .mint)
                rate("arrow.up", model.network?.totalOutPerSec, tint: .orange)
                Spacer(minLength: 0)
            }
            // Download trend — the same series the in-app chart leads with.
            WidgetSparkline(values: model.chartHistory.suffix(40).compactMap(\.netInPerSec), tint: .mint)
                .frame(maxHeight: .infinity)
                .frame(minHeight: 22 * scale)
            if let name = interfaceName {
                Text(name)
                    .scaledFont(10.5)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }

    private func rate(_ symbol: String, _ value: Double?, tint: Color) -> some View {
        HStack(spacing: 3 * scale) {
            Image(systemName: symbol)
                .scaledFont(11, weight: .semibold)
                .foregroundStyle(tint)
            Text(value.map(NetworkFormat.rate) ?? "—")
                .scaledFont(15, weight: .semibold, design: .rounded)
                .monospacedDigit()
                .numericTransition()
                .foregroundStyle(tint)
        }
    }

    /// The active interface's friendly name for the caption — the default-route
    /// link when known, else the first active one, else nil (no caption).
    private var interfaceName: String? {
        guard let network = model.network else { return nil }
        if let name = network.primaryInterfaceName,
           let link = network.links.first(where: { $0.name == name }) {
            return link.displayName
        }
        return network.links.first(where: { $0.isActive })?.displayName
    }
}
