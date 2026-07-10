import SwiftUI

/// Live disk throughput: whole-machine read / write rates with a read-trend
/// sparkline — the same `VitalsModel.diskIO` the dashboard reads. Both rates
/// show "—" until the second sample lands (a rate needs two readings), an
/// honest gap rather than a fabricated first value.
struct DiskWidget: View {
    @EnvironmentObject private var model: VitalsModel
    @Environment(\.widgetScale) private var scale

    var body: some View {
        WidgetCard(title: "Disk I/O", symbol: "internaldrive", tint: .yellow) {
            HStack(alignment: .firstTextBaseline, spacing: 12 * scale) {
                WidgetRateRow(symbol: "arrow.down", value: model.diskIO?.readPerSec, tint: .yellow)
                WidgetRateRow(symbol: "arrow.up", value: model.diskIO?.writePerSec, tint: .orange)
                Spacer(minLength: 0)
            }
            // Read trend — the same series the in-app chart leads with.
            WidgetSparkline(values: model.chartHistory.suffix(40).compactMap(\.diskReadPerSec), tint: .yellow)
                .frame(maxHeight: .infinity)
                .frame(minHeight: 22 * scale)
        }
    }

}
