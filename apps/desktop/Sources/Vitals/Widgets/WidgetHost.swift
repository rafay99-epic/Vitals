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

    // Handle on the real panel, plus the anchors captured at gesture start.
    @State private var window: NSWindow?
    @State private var dragMouse: CGPoint?
    @State private var dragOrigin: CGPoint?
    @State private var resizeMouse: CGPoint?
    @State private var resizeFrame: CGRect?

    var body: some View {
        ZStack {
            card
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
            }
            // Always in the tree (only *shown* on hover) so its gesture can
            // always claim a corner drag — otherwise the drag falls through to
            // the move gesture and the widget slides instead of resizing.
            resizeGrip.opacity(hovering ? 1 : 0)
        }
        // Make the whole body — including transparent corners — grabbable.
        .contentShape(Rectangle())
        .gesture(moveGesture)
        .background(WindowReader { window = $0 })
        .animation(.easeOut(duration: 0.12), value: hovering)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Close \(kind.shortTitle)", systemImage: "xmark") { onClose() }
        }
    }

    /// Drag the panel from anywhere on its body. Tracks the absolute mouse in
    /// screen coordinates against an anchor captured at the start, so the moving
    /// window can't feed back into the delta (a translation-based gesture jitters).
    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { _ in
                guard let window else { return }
                let mouse = NSEvent.mouseLocation
                if dragMouse == nil {
                    dragMouse = mouse
                    dragOrigin = window.frame.origin
                }
                guard let dm = dragMouse, let origin = dragOrigin else { return }
                window.setFrameOrigin(CGPoint(x: origin.x + (mouse.x - dm.x),
                                              y: origin.y + (mouse.y - dm.y)))
            }
            .onEnded { _ in
                dragMouse = nil
                dragOrigin = nil
                persistFrame()
            }
    }

    /// Bottom-right corner grip — revealed on hover, like the close button. Its
    /// own gesture wins over the move gesture inside this small hit target.
    private var resizeGrip: some View {
        VStack {
            Spacer(minLength: 0)
            HStack {
                Spacer(minLength: 0)
                Image(systemName: "arrow.down.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)        // generous hit target
                    .contentShape(Rectangle())
                    // High priority so the corner always resizes, beating the
                    // body's move gesture.
                    .highPriorityGesture(resizeGesture)
                    .help("Drag to resize")
            }
        }
        .padding(2)
    }

    /// Resize the panel anchored at its top-left (the corner stays put while the
    /// bottom-right follows the cursor), clamped to the kind's min/max.
    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { _ in
                guard let window else { return }
                let mouse = NSEvent.mouseLocation
                if resizeFrame == nil {
                    resizeFrame = window.frame
                    resizeMouse = mouse
                }
                guard let rf = resizeFrame, let rm = resizeMouse else { return }
                let width = min(max(rf.width + (mouse.x - rm.x), kind.minSize.width), kind.maxSize.width)
                let height = min(max(rf.height - (mouse.y - rm.y), kind.minSize.height), kind.maxSize.height)
                window.setFrame(CGRect(x: rf.minX, y: rf.maxY - height, width: width, height: height),
                                display: true)
            }
            .onEnded { _ in
                resizeFrame = nil
                resizeMouse = nil
                persistFrame()
            }
    }

    private func persistFrame() {
        guard let window else { return }
        let frame = window.frame
        UserDefaults.standard.set(
            [frame.origin.x, frame.origin.y, frame.width, frame.height],
            forKey: WidgetPanel.frameKey(for: kind)
        )
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
