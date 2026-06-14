import SwiftUI

/// Shared chrome for every desktop widget: a frosted rounded card with a tinted
/// icon-tile header — the same visual language as the in-app cards
/// (`Views/Components.swift`), sized for a small floating panel.
struct WidgetCard<Content: View>: View {
    let title: String
    let symbol: String
    let tint: Color
    /// 0–1 severity of this widget's reading. When animation is on, the card's
    /// rim lights up in `tint` and breathes with this value, so a hot/full/busy
    /// widget visibly warms up and a calm one is essentially still. Always a
    /// real reading — never decoration for its own sake.
    var intensity: Double = 0
    /// For the fan widget: 0–1 of rated RPM. Non-nil spins the icon tile at a
    /// speed proportional to the real RPM (nil / 0 = motionless).
    var spinFraction: Double? = nil
    @ViewBuilder var content: () -> Content

    @EnvironmentObject private var settings: AppSettings
    @State private var breathing = false

    /// Live rim strength: 0 when animation is off, otherwise the severity
    /// oscillating between full and half on the breathing cycle.
    private var glow: Double {
        guard settings.animateWidgets else { return 0 }
        return min(max(intensity, 0), 1) * (breathing ? 1.0 : 0.5)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                WidgetIconTile(symbol: symbol, tint: tint,
                               spinFraction: spinFraction, animate: settings.animateWidgets)
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            content()
            Spacer(minLength: 0)
        }
        .padding(13)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
                // Inner heat-tint that brightens with the reading.
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(tint.opacity(0.12 * glow))
                )
                // Resting hairline, always present.
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.separator.opacity(0.6), lineWidth: 1)
                )
                // Reactive rim that lights up in the tint.
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(tint.opacity(0.75 * glow), lineWidth: 1.2)
                )
        )
        .animation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true), value: breathing)
        .onAppear { breathing = true }
    }
}

/// The tinted icon tile in a widget header. For the fan widget it rotates at a
/// speed that tracks the real RPM (legibly scaled — a real fan at thousands of
/// RPM would strobe), and sits perfectly still at 0 RPM. Honest motion: the
/// blade only turns when the fan actually turns.
private struct WidgetIconTile: View {
    let symbol: String
    let tint: Color
    var spinFraction: Double? = nil
    var animate: Bool = false
    @State private var angle: Double = 0

    private var spinning: Bool { animate && (spinFraction ?? 0) > 0 }

    /// Seconds per revolution: ~3.6s near idle down to ~0.6s at rated RPM.
    private var period: Double {
        let f = min(max(spinFraction ?? 0, 0), 1)
        return 3.6 - 3.0 * f
    }

    /// Restart the spin whenever the speed bucket or the animate flag changes.
    private var spinKey: String {
        "\(animate)-\(Int(((spinFraction ?? 0) * 100).rounded()))"
    }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .medium))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
            .rotationEffect(.degrees(angle))
            .frame(width: 22, height: 22)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(tint.opacity(0.16))
            )
            .task(id: spinKey) { restartSpin() }
    }

    private func restartSpin() {
        // Snap back to rest, then ramp into a continuous turn if the fan is moving.
        withAnimation(.linear(duration: 0)) { angle = 0 }
        guard spinning else { return }
        withAnimation(.linear(duration: period).repeatForever(autoreverses: false)) {
            angle = 360
        }
    }
}

/// The SwiftUI root hosted inside each floating panel: picks the card for the
/// widget kind and adds a hover close button + context menu. The cards read the
/// shared `VitalsModel` / `AppSettings` injected by `WidgetPanel`.
struct WidgetHost: View {
    let kind: WidgetKind
    let onClose: () -> Void
    @State private var hovering = false

    var body: some View {
        ZStack {
            // Drag layer sits *under* the card; the card's content is
            // hit-test-disabled so a drag anywhere on the body reaches here.
            WidgetDragSurface(onClose: onClose)
            card.allowsHitTesting(false)
            if hovering {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(6)
                .transition(.opacity)
                .help("Close this widget")
                resizeGrip
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .onHover { hovering = $0 }
    }

    /// Bottom-right corner grip — revealed on hover, like the close button.
    private var resizeGrip: some View {
        ZStack {
            WidgetResizeGrip(minSize: kind.minSize, maxSize: kind.maxSize)
            Image(systemName: "arrow.down.right")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)
                .allowsHitTesting(false)
        }
        .frame(width: 16, height: 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .padding(5)
        .help("Drag to resize")
    }

    @ViewBuilder
    private var card: some View {
        switch kind {
        case .cpu: CPUWidget()
        case .cpuUsage: CPUUsageWidget()
        case .memory: MemoryWidget()
        case .fan: FanWidget()
        case .storage: StorageWidget()
        case .combined: CombinedWidget()
        }
    }
}
