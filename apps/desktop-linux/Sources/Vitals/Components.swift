import Adwaita
import Foundation
import VitalsCore

/// Value formatting for the dashboard. Honest about missing data: a `nil`
/// reading renders as an em dash, never a zero.
enum Fmt {
    static func temp(_ c: Double?) -> String { c.map { String(format: "%.0f°C", $0) } ?? "—" }
    static func degrees(_ c: Double) -> String { String(format: "%.0f°", c) }
    static func percent(_ p: Double?) -> String { p.map { String(format: "%.0f%%", $0) } ?? "—" }
    static func gigabytes(_ bytes: UInt64) -> String { String(format: "%.1f GB", Double(bytes) / 1_000_000_000) }
    static func watts(_ w: Double?) -> String { w.map { String(format: "%.1f W", $0) } ?? "—" }
}

extension SparklineRenderer.Color {
    /// Matches the macOS app and the website tokens.
    static let temp = SparklineRenderer.Color(1.0, 0.62, 0.29)     // orange
    static let cpu = SparklineRenderer.Color(0.20, 0.55, 0.95)     // blue
    static let memory = SparklineRenderer.Color(0.45, 0.40, 0.92)  // indigo
}

/// A label/value pair for the breakdown cards. `id` keeps `ForEach` stable even
/// when two rows share a label.
struct Row: Identifiable {
    let id: Int
    let label: String
    let value: String
}

func rows(_ pairs: [(String, String)]) -> [Row] {
    pairs.enumerated().map { Row(id: $0.offset, label: $0.element.0, value: $0.element.1) }
}

/// A hero stat card: caption, large value, sub-caption — the macOS dashboard's
/// top grid, in libadwaita's card style.
struct StatTile: View {
    let title: String
    let value: String
    let subtitle: String

    var view: Body {
        VStack {
            Text(title.uppercased())
                .caption()
                .dimLabel()
                .halign(.start)
            Text(value)
                .title1()
                .numeric()
                .halign(.start)
                .padding(2)
            Text(subtitle)
                .ellipsize()
                .caption()
                .dimLabel()
                .halign(.start)
        }
        .padding()
        .card()
        .hexpand()
        .padding(5)
    }
}

/// A titled card with a current value and a Cairo sparkline of recent history.
struct ChartCard: View {
    let title: String
    let value: String
    let series: [Double]
    let color: SparklineRenderer.Color
    /// Shown when there aren't yet two points to draw a line between.
    var emptyText = "Collecting…"

    var view: Body {
        VStack {
            HStack {
                Text(title).style("vitals-section").halign(.start).hexpand()
                Text(value).title3().numeric().halign(.end)
            }
            if series.count < 2 {
                Text(emptyText)
                    .caption()
                    .dimLabel()
                    .halign(.start)
                    .frame(minHeight: 64)
            } else {
                Picture()
                    .data(SparklineRenderer.render(values: series, width: 900, height: 72, line: color))
                    .hexpand()
            }
        }
        .padding()
        .card()
        .padding(6)
    }
}

/// A titled breakdown card — a list of label/value rows. Used for dies, fans,
/// processes, memory, and battery so they share one honest, consistent layout.
struct InfoCard: View {
    let title: String
    let entries: [Row]
    /// Shown when there's nothing to list (e.g. a fanless machine).
    var emptyText = "Nothing found"

    var view: Body {
        VStack {
            Text(title).heading().halign(.start).padding(2)
            if entries.isEmpty {
                Text(emptyText).dimLabel().halign(.start).padding(2)
            } else {
                ForEach(entries) { row in
                    HStack {
                        Text(row.label).ellipsize().halign(.start).hexpand()
                        Text(row.value).numeric().dimLabel().halign(.end)
                    }
                    .padding(3)
                }
            }
        }
        .padding()
        .card()
        .padding(5)
    }
}
