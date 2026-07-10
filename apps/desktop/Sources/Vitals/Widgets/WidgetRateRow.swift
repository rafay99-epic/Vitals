import SwiftUI

/// A compact "direction glyph + rate" pair — the hero row unit shared by the
/// throughput widgets (network, disk), extracted so the two can't drift. A "—"
/// value is the honest pre-baseline gap. When both rates on a row are wide
/// (e.g. "91.9 MB/s" beside "111.4 MB/s") the text scales down slightly
/// instead of truncating to an ellipsis — a shrunken real number beats a
/// chopped one.
struct WidgetRateRow: View {
    let symbol: String
    let value: Double?
    let tint: Color
    @Environment(\.widgetScale) private var scale

    var body: some View {
        HStack(spacing: 3 * scale) {
            Image(systemName: symbol)
                .scaledFont(11, weight: .semibold)
                .foregroundStyle(tint)
            Text(value.map(NetworkFormat.rate) ?? "—")
                .scaledFont(15, weight: .semibold, design: .rounded)
                .monospacedDigit()
                .numericTransition()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(tint)
        }
    }
}
