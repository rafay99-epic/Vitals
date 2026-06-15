import SwiftUI
import Charts

// MARK: - Empty / idle state

/// A short, scannable hint chip used under an empty state to preview what the
/// action surfaces (e.g. "Largest folders").
struct EmptyStateHint: Identifiable {
    let symbol: String
    let label: String
    var id: String { label }
}

/// The shared, polished empty/idle state: a tinted icon tile lifted off a soft
/// glow, a headline, supporting copy, optional preview chips, and the primary
/// action. One look for every "nothing here yet" moment so the app reads as a
/// single, considered surface rather than a stack of placeholders.
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

/// The loading sibling of `EmptyStateView`: same card chrome, a spinner where
/// the icon tile sits. Used for the first-data fetch on tabs that don't have a
/// card skeleton to show meanwhile.
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

// MARK: - Tab scaffold

/// A monitoring tab's scrolling canvas, batched into one Liquid Glass pass when
/// enabled — the shared chrome behind the GPU, Battery and Health tabs, matching
/// the Dashboard's `LazyVStack` + `GlassEffectContainer` so every surface reads
/// as one app. Lazy, so off-screen cards cost nothing until scrolled to.
struct MetricScroll<Content: View>: View {
    @EnvironmentObject private var settings: AppSettings
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            batched
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var batched: some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *), settings.glassEnabled {
            GlassEffectContainer { stack }
        } else {
            stack
        }
        #else
        stack
        #endif
    }

    private var stack: some View {
        LazyVStack(alignment: .leading, spacing: 16, content: content)
    }
}

// MARK: - Cards

struct StatCard: View {
    let title: String
    let value: String
    let subtitle: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(tint.opacity(0.14))
                    )
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .numericTransition()
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
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
        // maxHeight so paired cards in a row share the row's height (the
        // background fills instead of leaving the shorter card stranded). In a
        // vertical scroll the proposed height is the ideal, so it doesn't stretch.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
        .cardBackground()
    }
}

/// A compact power readout tile in the shared card language. Shared by the GPU
/// and Health tabs.
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
        if #available(macOS 26.0, *), settings.glassEnabled {
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
/// standard opaque window color otherwise. The frosting slider in Settings
/// picks how much of the desktop blurs through.
struct WindowBackdrop: ViewModifier {
    @EnvironmentObject private var settings: AppSettings

    @ViewBuilder
    func body(content: Content) -> some View {
        if settings.glassEnabled {
            content.containerBackground(backdropMaterial, for: .window)
        } else {
            content.background(Color(nsColor: .windowBackgroundColor))
        }
    }

    private var backdropMaterial: Material {
        switch settings.glassIntensity {
        case ..<0.2: return .ultraThinMaterial
        case ..<0.4: return .thinMaterial
        case ..<0.6: return .regularMaterial
        case ..<0.8: return .thickMaterial
        default: return .ultraThickMaterial
        }
    }
}

// MARK: - Deferred mounting

/// Mounts expensive content (Swift Charts cost 50–150 ms on first layout)
/// just after the view appears, so window-open and sidebar animations run
/// against an empty placeholder of the same size instead of paying chart
/// setup mid-animation. The placeholder is Color.clear — a real view, so
/// `.task` reliably fires.
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
            withAnimation(.easeIn(duration: 0.18)) { ready = true }
        }
    }
}

// MARK: - Animation gating

/// Whether views in this subtree may run continuous animations. Off when GPU
/// acceleration is disabled or Vitals isn't the focused app. Defaults to `true`,
/// so any surface that doesn't inject it keeps animating (safe fallback). The
/// live surfaces (dashboard, menu bar, widgets) inject `settings.animationsEnabled`.
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
    /// Animate digit changes with `.numericText()` — but only where
    /// `\.animationsEnabled` is true. Snaps with `.identity` otherwise, so no
    /// per-tick transition runs while the app is backgrounded or accel is off.
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

/// 0 at ≤40 °C rising to 1 at ≥90 °C — the same ramp `tempGradientColor` uses,
/// exposed for driving widget glow intensity from a real temperature.
func tempSeverity(_ celsius: Double) -> Double {
    min(max((celsius - 40) / 50, 0), 1)
}

func gigabytes(_ bytes: UInt64) -> Double {
    Double(bytes) / 1_073_741_824
}

func gigabytes(_ bytes: Double) -> Double {
    bytes / 1_073_741_824
}

/// Color for the macOS memory-pressure level — green/yellow/red like
/// Activity Monitor's pressure graph.
func pressureColor(_ pressure: MemoryPressure) -> Color {
    switch pressure {
    case .normal: return .green
    case .warning: return .yellow
    case .critical: return .red
    }
}
