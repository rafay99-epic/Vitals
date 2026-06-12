import SwiftUI
import Charts

// MARK: - Cards

struct StatCard: View {
    let title: String
    let value: String
    let subtitle: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .foregroundStyle(tint)
                Text(title)
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            Text(value)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .contentTransition(.numericText())
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .cardBackground()
    }
}

struct SectionCard<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .foregroundStyle(.secondary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .cardBackground()
    }
}

extension View {
    func cardBackground() -> some View {
        modifier(CardBackground())
    }
}

/// Card chrome: Liquid Glass on macOS 26 when enabled, classic bordered
/// fill otherwise.
struct CardBackground: ViewModifier {
    @EnvironmentObject private var settings: AppSettings

    @ViewBuilder
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *), settings.liquidGlass {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            classic(content)
        }
        #else
        classic(content)
        #endif
    }

    private func classic(_ content: Content) -> some View {
        content.background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.separator, lineWidth: 1)
                )
        )
    }
}

/// Window backdrop: a translucent material when Liquid Glass is on, the
/// standard opaque window color otherwise.
struct WindowBackdrop: ViewModifier {
    @EnvironmentObject private var settings: AppSettings

    @ViewBuilder
    func body(content: Content) -> some View {
        if settings.liquidGlass {
            content.containerBackground(.ultraThinMaterial, for: .window)
        } else {
            content.background(Color(nsColor: .windowBackgroundColor))
        }
    }
}

// MARK: - Chart hover support

/// Tracks the cursor over a chart's plot area and reports the date under it.
extension View {
    func chartHover(_ hoverTime: Binding<Date?>) -> some View {
        chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            guard let plotFrame = proxy.plotFrame else { return }
                            let x = location.x - geometry[plotFrame].origin.x
                            hoverTime.wrappedValue = proxy.value(atX: x)
                        case .ended:
                            hoverTime.wrappedValue = nil
                        }
                    }
            }
        }
    }
}

struct HoverTooltip<Rows: View>: View {
    let time: Date
    @ViewBuilder let rows: Rows

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(time, format: .dateTime.hour().minute().second())
                .foregroundStyle(.secondary)
            rows
        }
        .font(.caption2)
        .monospacedDigit()
        .padding(6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
    }
}

extension Array where Element == VitalsModel.Sample {
    func nearest(to time: Date?) -> VitalsModel.Sample? {
        guard let time else { return nil }
        return self.min {
            abs($0.time.timeIntervalSince(time)) < abs($1.time.timeIntervalSince(time))
        }
    }
}

// MARK: - Helpers

/// Continuous severity color: green at ≤40 °C sliding to red at ≥90 °C.
/// Input is always °C regardless of the display unit.
func tempGradientColor(_ celsius: Double) -> Color {
    let t = min(max((celsius - 40) / 50, 0), 1)
    return Color(hue: 0.33 * (1 - t), saturation: 0.85, brightness: 0.88)
}

func gigabytes(_ bytes: UInt64) -> Double {
    Double(bytes) / 1_073_741_824
}
