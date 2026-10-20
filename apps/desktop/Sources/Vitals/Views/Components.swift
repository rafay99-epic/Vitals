import SwiftUI

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
