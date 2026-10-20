import SwiftUI
import Charts

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

/// Draws the hover rule and tooltip in the chart's overlay. The hover state
/// lives in the overlay, so moving the cursor never rebuilds the chart's marks.
extension View {
    func chartHover<Rows: View>(
        samples: [VitalsModel.Sample],
        @ViewBuilder tooltip: @escaping (VitalsModel.Sample) -> Rows
    ) -> some View {
        chartOverlay { proxy in
            ChartHoverLayer(proxy: proxy, samples: samples, tooltip: tooltip)
        }
    }
}

private struct ChartHoverLayer<Rows: View>: View {
    let proxy: ChartProxy
    let samples: [VitalsModel.Sample]
    let tooltip: (VitalsModel.Sample) -> Rows
    @State private var hoverTime: Date?

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            guard let plotFrame = proxy.plotFrame else { return }
                            hoverTime = proxy.value(atX: location.x - geometry[plotFrame].origin.x)
                        case .ended:
                            hoverTime = nil
                        }
                    }
                if let plotFrame = proxy.plotFrame,
                   let sample = samples.nearest(to: hoverTime),
                   let x = proxy.position(forX: sample.time) {
                    let frame = geometry[plotFrame]
                    Rectangle()
                        .fill(.secondary.opacity(0.5))
                        .frame(width: 1, height: frame.height)
                        .position(x: frame.minX + x, y: frame.midY)
                        .allowsHitTesting(false)
                    HoverTooltip(time: sample.time) { tooltip(sample) }
                        .fixedSize()
                        .position(x: min(max(frame.minX + x, frame.minX + 70), frame.maxX - 70), y: frame.minY + 24)
                        .allowsHitTesting(false)
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

/// One shared formatter: the class-method form allocates per call, and size
/// labels render across hundreds of rows.
@MainActor private let byteFormatter: ByteCountFormatter = {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter
}()

@MainActor func formatBytes(_ bytes: UInt64) -> String {
    byteFormatter.string(fromByteCount: Int64(bytes))
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
