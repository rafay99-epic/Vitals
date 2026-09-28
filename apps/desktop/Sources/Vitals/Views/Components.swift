import SwiftUI
import Charts

// MARK: - Empty / idle state

/// A short hint chip shown under an empty state's copy.
struct EmptyStateHint: Identifiable {
    let symbol: String
    let label: String
    var id: String { label }
}

/// The shared empty/idle state: icon tile, headline, supporting copy,
/// optional hint chips, and the primary action.
struct EmptyStateView<Actions: View>: View {
    let symbol: String
    let tint: Color
    let title: String
    let message: String
    var hints: [EmptyStateHint] = []
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(spacing: 16) {
            icon
            VStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 430)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !hints.isEmpty {
                HStack(spacing: 8) {
                    ForEach(hints) { hint in
                        HStack(spacing: 5) {
                            Image(systemName: hint.symbol)
                                .font(.system(size: 10, weight: .semibold))
                            Text(hint.label)
                                .font(.caption2.weight(.medium))
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(.quaternary.opacity(0.5)))
                    }
                }
                .padding(.top, 2)
            }
            actions()
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .padding(.horizontal, 20)
        .cardBackground()
    }

    private var icon: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.18))
                .frame(width: 92, height: 92)
                .blur(radius: 22)
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [tint.opacity(0.28), tint.opacity(0.10)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: 64, height: 64)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(tint.opacity(0.30), lineWidth: 1)
                )
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
        }
    }
}

/// The loading sibling of `EmptyStateView`: same chrome, a spinner in place
/// of the icon tile.
struct LoadingStateView: View {
    let title: String
    var message: String?

    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
                .frame(height: 64)
            VStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                if let message {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .padding(.horizontal, 20)
        .cardBackground()
    }
}

// MARK: - Section scaffold

/// A monitoring section's scrolling canvas. Lazy, so off-screen cards cost
/// nothing until scrolled to.
struct MetricScroll<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16, content: content)
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Cards

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
        // maxHeight lets paired cards in a row share the row's height. In a vertical
        // scroll the proposed height is the ideal, so it doesn't stretch.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
        .cardBackground()
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
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(tint.opacity(0.14)))
                Text(title).font(.system(size: 12.5, weight: .medium)).foregroundStyle(.secondary)
            }
            Text(wattsText(watts))
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .numericTransition()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.quaternary.opacity(0.3)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator.opacity(0.5)))
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

extension View {
    /// The shared card chrome: radius 12, control fill, hairline border.
    func cardBackground() -> some View {
        background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.separator, lineWidth: 1)
                )
        )
    }
}

// MARK: - Deferred mounting

/// Mounts expensive content (Swift Charts cost 50-150 ms on first layout) just
/// after appear, so window-open animates against a same-size placeholder.
/// `Color.clear` is a real view so `.task` fires. The mount is not animated,
/// so it can't hitch a surrounding spring.
struct Deferred<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @State private var ready = false

    var body: some View {
        ZStack {
            if ready {
                content()
            } else {
                Color.clear
            }
        }
        .task {
            guard !ready else { return }
            // Let the open animation get going before mounting.
            try? await Task.sleep(for: .milliseconds(90))
            ready = true
        }
    }
}

// MARK: - Animation gating

/// Whether views in this subtree may animate value changes. The main window
/// injects `settings.appActive`, so nothing animates while Vitals is in the
/// background. Defaults to `true` elsewhere (the menu-bar dropdown).
private struct AnimationsEnabledKey: EnvironmentKey { static let defaultValue = true }

extension EnvironmentValues {
    var animationsEnabled: Bool {
        get { self[AnimationsEnabledKey.self] }
        set { self[AnimationsEnabledKey.self] = newValue }
    }
}

private struct NumericTransition: ViewModifier {
    @Environment(\.animationsEnabled) private var enabled
    func body(content: Content) -> some View {
        content.contentTransition(enabled ? .numericText() : .identity)
    }
}

extension View {
    /// `.numericText()` digit animation, or `.identity` when `\.animationsEnabled`
    /// is false, so no per-tick transition runs while backgrounded.
    func numericTransition() -> some View { modifier(NumericTransition()) }
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
    /// Closest sample to `time` by binary search (samples are in ascending time
    /// order). Runs on every hover move over a chart.
    func nearest(to time: Date?) -> VitalsModel.Sample? {
        guard let time, !isEmpty else { return nil }
        var lo = 0, hi = count - 1
        if time <= self[lo].time { return self[lo] }
        if time >= self[hi].time { return self[hi] }
        while lo < hi {
            let mid = (lo + hi) / 2
            if self[mid].time < time { lo = mid + 1 } else { hi = mid }
        }
        // `lo` is the first index whose time >= target; nearest is it or the one before.
        guard lo > 0 else { return self[lo] }
        let after = self[lo], before = self[lo - 1]
        return abs(before.time.timeIntervalSince(time)) <= abs(after.time.timeIntervalSince(time)) ? before : after
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

func gigabytes(_ bytes: Double) -> Double {
    bytes / 1_073_741_824
}

/// Swap as "used of total", or "None" when no swap is configured.
func swapSummary(_ memory: MemorySnapshot) -> String {
    guard memory.swapTotal > 0 else { return "None" }
    return String(format: "%.2f GB of %.1f GB", gigabytes(memory.swapUsed), gigabytes(memory.swapTotal))
}

/// Color for the macOS memory-pressure level: green/yellow/red like
/// Activity Monitor's pressure graph.
func pressureColor(_ pressure: MemoryPressure) -> Color {
    switch pressure {
    case .normal: return .green
    case .warning: return .yellow
    case .critical: return .red
    }
}
