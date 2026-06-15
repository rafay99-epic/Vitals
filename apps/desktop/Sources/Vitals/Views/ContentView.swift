import SwiftUI

/// Top-level navigation: a stationary header with segmented tabs over one
/// fixed content canvas — Activity Monitor style. There is no sidebar and no
/// window toolbar, so nothing can resize or snap the content, ever: tab
/// switches change what's drawn, never the geometry it's drawn in.
struct ContentView: View {
    enum Section: String, CaseIterable, Identifiable {
        case dashboard, processes, applications, cleanup, storage
        var id: String { rawValue }

        var title: String {
            switch self {
            case .dashboard: return "Dashboard"
            case .processes: return "Processes"
            case .applications: return "Applications"
            case .cleanup: return "Cleanup"
            case .storage: return "Storage"
            }
        }

        var symbol: String {
            switch self {
            case .dashboard: return "gauge.with.dots.needle.50percent"
            case .processes: return "list.bullet"
            case .applications: return "square.grid.2x2"
            case .cleanup: return "sparkles"
            case .storage: return "internaldrive"
            }
        }

        var shortcut: KeyEquivalent {
            switch self {
            case .dashboard: return "1"
            case .processes: return "2"
            case .applications: return "3"
            case .cleanup: return "4"
            case .storage: return "5"
            }
        }
    }

    @State private var section: Section = .dashboard
    @State private var gearHovered = false
    @Environment(\.openWindow) private var openWindow
    @Namespace private var tabIndicator
    // Owned here so the scans survive section switches — recreating these per
    // visit meant a full rescan (and a "Scanning…" flash) every time.
    @StateObject private var processesModel = ProcessesModel()
    @StateObject private var appsModel = AppsModel()
    @StateObject private var cleanupModel = CleanupModel()
    @StateObject private var storageModel = StorageModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
                .opacity(0.5)
            ZStack {
                // The Dashboard stays mounted across tab switches: its Swift
                // Charts cost 50–150 ms each to build, so rebuilding them on
                // every visit caused a visible hitch. Kept alive (just hidden),
                // returning to it is instant. Hidden, it isn't drawn — only the
                // light per-tick data refresh runs, which lean mode keeps cheap.
                DashboardView()
                    .opacity(section == .dashboard ? 1 : 0)
                    .allowsHitTesting(section == .dashboard)
                    .accessibilityHidden(section != .dashboard)

                // The list-based tabs are cheap to rebuild and some refresh on
                // appear (Storage re-reads volume/access), so they stay
                // build-on-demand to preserve that.
                switch section {
                case .dashboard: EmptyView()
                case .processes: ProcessesView(model: processesModel)
                case .applications: AppsView(model: appsModel)
                case .cleanup: CleanupView(model: cleanupModel)
                case .storage: StorageView(model: storageModel)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // The hidden title bar still reserves a safe-area strip; claim it so
        // the header shares the row with the traffic lights instead of
        // leaving a dead band above itself.
        .ignoresSafeArea(edges: .top)
        .modifier(WindowBackdrop())
        .frame(minWidth: 980, minHeight: 680)
    }

    // MARK: Header

    /// The title bar replacement: branding, centered tabs, settings — one
    /// row shared with the traffic lights. It also drags the window, since
    /// the system title bar is hidden.
    private var header: some View {
        ZStack {
            HStack(spacing: 9) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 26, height: 26)
                Text("Vitals")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button {
                    openWindow(id: "settings")
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(.quaternary.opacity(gearHovered ? 0.7 : 0)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.12)) { gearHovered = hovering }
                }
                .help("Vitals settings")
            }
            tabBar
        }
        .padding(.leading, 84)  // clear the traffic lights
        .padding(.trailing, 12)
        .frame(height: 46)
        .contentShape(Rectangle())
        .gesture(WindowDragGesture())
    }

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(Section.allCases) { item in
                tabButton(item)
            }
        }
        .padding(3)
        .background(Capsule().fill(.quaternary.opacity(0.45)))
    }

    private func tabButton(_ item: Section) -> some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                section = item
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: item.symbol)
                    .font(.system(size: 12, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                Text(item.title)
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 6)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(section == item ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        .background {
            if section == item {
                Capsule()
                    .fill(.quaternary)
                    .matchedGeometryEffect(id: "selected-tab", in: tabIndicator)
            }
        }
        .keyboardShortcut(item.shortcut, modifiers: .command)
        .help("\(item.title) (⌘\(item.shortcut.character))")
    }
}

/// The original live dashboard, unchanged — now one section of the window.
struct DashboardView: View {
    @EnvironmentObject private var model: VitalsModel
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        ScrollView {
            Group {
                if !model.hasLoaded {
                    LoadingStateView(
                        title: "Reading sensors",
                        message: "Vitals is taking its first measurement of this Mac's temperatures, fans, and memory."
                    )
                } else if model.sensorsUnavailable {
                    EmptyStateView(
                        symbol: "sensor.tag.radiowaves.forward.fill",
                        tint: .orange,
                        title: "No sensor data",
                        message: "Vitals couldn't read this Mac's temperature, fan, or memory sensors. This usually means a virtual machine or restricted hardware access — readings will appear here once they're available."
                    ) {
                        EmptyView()
                    }
                } else {
                    glassBatched
                }
            }
            .padding(20)
        }
    }

    /// On macOS 26 with Liquid Glass on, every card is its own glass surface
    /// — a dozen independent backdrop captures re-rendered each frame of the
    /// sidebar/window animation. GlassEffectContainer batches them into one
    /// render pass, which is most of the "freeze before it moves" fix.
    @ViewBuilder
    private var glassBatched: some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *), settings.glassEnabled {
            GlassEffectContainer {
                cards
            }
        } else {
            cards
        }
        #else
        cards
        #endif
    }

    /// Lazy so the window's first frame (and every frame of a resize
    /// animation) only builds and lays out the cards actually on screen —
    /// the heavy below-the-fold charts no longer tax open/close/toggle.
    private var cards: some View {
        LazyVStack(alignment: .leading, spacing: 16) {
            UpdateBanner()
            DashboardHero()
            PerformanceHistoryCard()
            HStack(alignment: .top, spacing: 16) {
                CPUCard()
                GPUCard()
            }
            HStack(alignment: .top, spacing: 16) {
                MemoryCard()
                FanCard()
            }
            CollapsibleCard(
                title: "Top processes",
                symbol: "list.bullet.rectangle",
                subtitle: model.topProcesses.first.map { String(format: "%@ · %.0f%%", $0.name, $0.cpuPercent) }
            ) {
                TopProcessesContent()
            }
            CollapsibleCard(
                title: "Battery",
                symbol: BatteryContent.symbol(for: model.battery),
                subtitle: model.battery.map { "\(Int($0.percent))%" }
            ) {
                BatteryContent()
            }
            footer
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Text(HardwareInfo.chipName)
            Text("·")
            Text(HardwareInfo.osVersion)
            Text("·")
            Text("Up \(HardwareInfo.uptimeText)")
            if let ssd = model.ssdTemp {
                Text("·")
                Text("SSD \(settings.format(ssd, decimals: 0))")
            }
            if let battery = model.batteryTemp {
                Text("·")
                Text("Battery \(settings.format(battery, decimals: 0))")
            }
            Spacer()
            Text("Updates every \(settings.refreshInterval, format: .number) s")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }
}

/// Shown at the top of the dashboard while an update is available or installing.
struct UpdateBanner: View {
    @EnvironmentObject private var updater: Updater

    var body: some View {
        switch updater.status {
        case .available(let release):
            banner {
                Label("Vitals \(release.version) is available", systemImage: "arrow.down.circle.fill")
                    .foregroundStyle(.blue)
                Text("You're on \(Updater.currentVersion)")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Install Update") {
                    Task { await updater.downloadAndInstall() }
                }
                .buttonStyle(.borderedProminent)
            }
        case .downloading:
            banner {
                Label("Downloading update…", systemImage: "arrow.down.circle")
                Spacer()
                ProgressView().controlSize(.small)
            }
        case .installing:
            banner {
                Label("Installing — Vitals will relaunch in a moment", systemImage: "gearshape.arrow.triangle.2.circlepath")
                Spacer()
                ProgressView().controlSize(.small)
            }
        default:
            EmptyView()
        }
    }

    private func banner<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10, content: content)
            .font(.callout)
            .padding(12)
            .cardBackground()
    }
}
