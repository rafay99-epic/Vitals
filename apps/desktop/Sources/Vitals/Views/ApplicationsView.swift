import SwiftUI

/// The Applications tab: one control center for everything app-shaped — what's
/// installed (and removable, leftovers and all) and what launches itself at
/// startup. Two distinct jobs with different risk levels, kept as sibling
/// segments rather than one fused list, reusing `AppsView` and `LoginItemsView`
/// verbatim (one component each, never a copy).
struct ApplicationsView: View {
    /// Owned by `TabCanvas` so a scan survives switching tabs.
    @ObservedObject var appsModel: AppsModel
    @ObservedObject var loginItemsModel: LoginItemsModel
    /// True only while Applications is the visible tab.
    let isActive: Bool

    @State private var segment: Segment = .installed
    @State private var visited: Set<Segment> = [.installed]

    enum Segment: String, CaseIterable, Identifiable {
        case installed, startup
        var id: String { rawValue }
        var title: String { self == .installed ? "Installed" : "Startup" }
        var symbol: String { self == .installed ? "square.grid.2x2" : "power" }
    }

    var body: some View {
        VStack(spacing: 0) {
            SegmentControl(items: Segment.allCases, selection: $segment,
                           title: \.title, symbol: \.symbol,
                           onSelect: { visited.insert($0) })
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)
            Divider().opacity(0.5)
            canvas
        }
    }

    /// Mirrors `SystemView`/`TabCanvas`: segments mount lazily, then stay alive
    /// (kept-mounted, hidden) so switching back is instant and a scan keeps
    /// running. Each view starts/stops its own work on its per-segment `isActive`.
    private var canvas: some View {
        ZStack {
            if visited.contains(.installed) {
                AppsView(model: appsModel, isActive: active(.installed))
                    .tabVisibility(segment == .installed)
            }
            if visited.contains(.startup) {
                LoginItemsView(model: loginItemsModel, isActive: active(.startup))
                    .tabVisibility(segment == .startup)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(nil, value: segment)
    }

    private func active(_ seg: Segment) -> Bool { isActive && segment == seg }
}
