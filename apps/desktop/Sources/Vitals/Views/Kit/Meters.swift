import SwiftUI

/// A fraction-filled bar in the card language, used by the GPU and CPU meters.
func utilizationBar(fraction: Double, tint: Color) -> some View {
    GeometryReader { geometry in
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 5, style: .continuous).fill(.secondary.opacity(0.15))
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(tint)
                .frame(width: geometry.size.width * min(max(fraction, 0), 1))
        }
    }
    .frame(height: 12)
}

/// A labelled utilisation meter (label, bar, %) for the CPU cluster and
/// per-core rows.
struct ClusterMeter: View {
    let label: String
    let percent: Double
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Text(label).font(.caption).foregroundStyle(.secondary).frame(width: 82, alignment: .leading)
            utilizationBar(fraction: percent / 100, tint: tint)
            Text(String(format: "%.0f%%", percent))
                .font(.caption).monospacedDigit().numericTransition()
                .frame(width: 38, alignment: .trailing)
        }
    }
}

/// A labelled stat column (caption, rounded mono value, optional note), used
/// by the CPU and Sensors temperature cards.
func statColumn(_ label: String, _ value: String, note: String? = nil) -> some View {
    VStack(alignment: .leading, spacing: 2) {
        Text(label).font(.caption).foregroundStyle(.secondary)
        Text(value)
            .font(.system(size: 22, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .numericTransition()
        if let note {
            Text(note).font(.caption2).foregroundStyle(.tertiary)
        }
    }
}

struct LegendSwatch: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 9, height: 9)
            Text(label)
        }
    }
}

struct MetricRow: Identifiable {
    let symbol: String
    let label: String
    let value: String
    var id: String { label }
}

/// A two-column key/value grid. Fixed columns (never `.adaptive`) so it
/// doesn't reflow mid-animation.
struct MetricRowGrid: View {
    let rows: [MetricRow]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading),
                            GridItem(.flexible(), alignment: .leading)],
                  spacing: 10) {
            ForEach(rows) { row in
                HStack(spacing: 8) {
                    Image(systemName: row.symbol)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 18)
                    Text(row.label).font(.callout).foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(row.value)
                        .font(.system(.callout, design: .rounded, weight: .medium))
                        .monospacedDigit()
                        .numericTransition()
                }
            }
        }
    }
}

/// One power rail readout tile, laid out by `PowerRails`.
struct PowerTile: View {
    let title: String
    let watts: Double
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                IconTile(symbol: symbol, tint: tint)
                Text(title).font(.system(size: 12.5, weight: .medium)).foregroundStyle(.secondary)
            }
            Text(wattsText(watts))
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .numericTransition()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .insetCard()
    }
}

/// Watts with a sensible precision: sub-watt rails (an idle Neural Engine) keep
/// two decimals so they don't collapse to a flat "0 W".
func wattsText(_ watts: Double) -> String {
    watts < 10 ? String(format: "%.2f W", watts) : String(format: "%.1f W", watts)
}

/// The SoC power rails (CPU / GPU / Neural Engine) as tiles plus the package
/// total. Every power card uses this body.
struct PowerRails: View {
    let power: PowerSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                PowerTile(title: "CPU", watts: power.cpuWatts, symbol: "cpu", tint: .blue)
                PowerTile(title: "GPU", watts: power.gpuWatts, symbol: "cpu.fill", tint: .purple)
                PowerTile(title: "Neural Engine", watts: power.aneWatts, symbol: "brain", tint: .pink)
            }
            HStack {
                Text("Total package").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Text(wattsText(power.total))
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .numericTransition()
            }
        }
    }
}
