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
    @Environment(\.widgetScale) private var scale
    @State private var breathing = false

    /// Whether the rim should breathe: the user's widget-animation preference,
    /// gated by the global animation switch (GPU acceleration on + app focused).
    private var animating: Bool { settings.animationsEnabled && settings.animateWidgets }

    /// Live rim strength. Off entirely when the user disables widget animation.
    /// When frozen by the global switch (backgrounded / accel off) the rim holds
    /// steady at the real severity rather than oscillating — a still fill costs
    /// nothing per frame.
    private var glow: Double {
        guard settings.animateWidgets else { return 0 }
        let base = min(max(intensity, 0), 1)
        guard settings.animationsEnabled else { return base }
        return base * (breathing ? 1.0 : 0.5)
    }

    private var corner: CGFloat { 16 * scale }

    var body: some View {
        VStack(alignment: .leading, spacing: 8 * scale) {
            HStack(spacing: 7 * scale) {
                WidgetIconTile(symbol: symbol, tint: tint,
                               spinFraction: spinFraction, animate: animating)
                Text(title)
                    .scaledFont(11.5, weight: .medium)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            content()
            Spacer(minLength: 0)
        }
        .padding(13 * scale)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(.regularMaterial)
                // Inner heat-tint that brightens with the reading.
                .overlay(
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(tint.opacity(0.12 * glow))
                )
                // Resting hairline, always present.
                .overlay(
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .strokeBorder(.separator.opacity(0.6), lineWidth: 1)
                )
                // Reactive rim that lights up in the tint.
                .overlay(
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .strokeBorder(tint.opacity(0.75 * glow), lineWidth: 1.2)
                )
        )
        // Only the live, breathing rim runs a repeating animation; when frozen
        // the glow is a steady fill with no per-frame work.
        .animation(animating ? .easeInOut(duration: 2.2).repeatForever(autoreverses: true) : .default, value: breathing)
        .onAppear { breathing = animating }
        .onChange(of: animating) { _, on in breathing = on }
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
    @Environment(\.widgetScale) private var scale
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
            .scaledFont(11, weight: .medium)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
            .rotationEffect(.degrees(angle))
            .frame(width: 22 * scale, height: 22 * scale)
            .background(
                RoundedRectangle(cornerRadius: 6 * scale, style: .continuous).fill(tint.opacity(0.16))
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
    /// Reports a finished move/resize so the manager can remember the frame
    /// in the *current display arrangement's* layout (the host has no idea
    /// which arrangement it's on — that seam lives in `WidgetManager`).
    let onFrameChanged: (CGRect) -> Void
    @EnvironmentObject private var settings: AppSettings
    @State private var hovering = false

    /// A single drag either moves or resizes, decided once from where it began.
    private enum DragMode { case move, resize }
    /// Size of the bottom-right zone that resizes instead of moves.
    private let resizeCorner: CGFloat = 30

    // Handle on the real panel, plus the mode + anchors captured at drag start.
    @State private var window: NSWindow?
    @State private var dragMode: DragMode?
    @State private var anchorMouse: CGPoint?
    @State private var anchorFrame: CGRect?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                card
                if hovering {
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .scaledFont(15)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(6)
                    .transition(.opacity)
                    .help("Close this widget")
                }
                // Always in the tree (only *shown* on hover) so its gesture can
                // always claim a corner drag — otherwise the drag falls through to
                // the move gesture and the widget slides instead of resizing.
                resizeGrip.opacity(hovering ? 1 : 0)
            }
            // Scale content to the panel so a resized widget fills, not strands.
            .environment(\.widgetScale, widgetScale(for: geo.size, default: kind.defaultSize))
            // Make the whole body — including transparent corners — grabbable.
            .contentShape(Rectangle())
            .environment(\.animationsEnabled, settings.animationsEnabled)
            .gesture(dragGesture(in: geo.size))
            .background(WindowReader { window = $0 })
            .animation(.easeOut(duration: 0.12), value: hovering)
            .onHover { hovering = $0 }
            .contextMenu {
                Button("Close \(kind.shortTitle)", systemImage: "xmark") { onClose() }
            }
        }
    }

    /// One gesture for the whole body. The first move locks in a mode: a drag
    /// that starts in the bottom-right corner resizes (top-left pinned), anything
    /// else moves. Both track the absolute mouse in screen coordinates against an
    /// anchor captured at the start, so the moving/resizing window can't feed back
    /// into the delta (a translation-based gesture jitters). One gesture means no
    /// move-vs-resize priority fight — the bug that broke resize.
    private func dragGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .local)
            .onChanged { value in
                guard let window else { return }
                if dragMode == nil {
                    let inCorner = value.startLocation.x >= size.width - resizeCorner
                        && value.startLocation.y >= size.height - resizeCorner
                    dragMode = inCorner ? .resize : .move
                    anchorMouse = NSEvent.mouseLocation
                    anchorFrame = window.frame
                }
                guard let mode = dragMode, let am = anchorMouse, let af = anchorFrame else { return }
                let mouse = NSEvent.mouseLocation
                switch mode {
                case .move:
                    window.setFrameOrigin(CGPoint(x: af.origin.x + (mouse.x - am.x),
                                                  y: af.origin.y + (mouse.y - am.y)))
                case .resize:
                    let width = min(max(af.width + (mouse.x - am.x), kind.minSize.width), kind.maxSize.width)
                    let height = min(max(af.height - (mouse.y - am.y), kind.minSize.height), kind.maxSize.height)
                    // Top-left stays put (AppKit origin is bottom-left).
                    window.setFrame(CGRect(x: af.minX, y: af.maxY - height, width: width, height: height),
                                    display: true)
                }
            }
            .onEnded { _ in
                dragMode = nil
                anchorMouse = nil
                anchorFrame = nil
                persistFrame()
            }
    }

    /// Bottom-right grip — a hover-revealed affordance only; the unified drag
    /// gesture (above) handles the actual resize when a drag starts in this corner.
    private var resizeGrip: some View {
        VStack {
            Spacer(minLength: 0)
            HStack {
                Spacer(minLength: 0)
                Image(systemName: "arrow.down.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .allowsHitTesting(false)
                    .help("Drag to resize")
            }
        }
        .padding(2)
    }

    private func persistFrame() {
        guard let window else { return }
        onFrameChanged(window.frame)
    }

    @ViewBuilder
    private var card: some View {
        switch kind {
        case .cpu: CPUWidget()
        case .cpuUsage: CPUUsageWidget()
        case .gpu: GPUWidget()
        case .memory: MemoryWidget()
        case .battery: BatteryWidget()
        case .fan: FanWidget()
        case .network: NetworkWidget()
        case .storage: StorageWidget()
        case .combined: CombinedWidget()
        }
    }
}
