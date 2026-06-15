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
    // Owned here so the scans survive section switches.
    @StateObject private var processesModel = ProcessesModel()
    @StateObject private var appsModel = AppsModel()
    @StateObject private var cleanupModel = CleanupModel()
    @StateObject private var storageModel = StorageModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
                .opacity(0.5)
            // Every tab is mounted once and kept alive — switching only toggles
            // which one is visible. Re-mounting a tab is the expensive step
            // (NSTableViews, Swift Charts, and especially Liquid Glass surfaces,
            // which flash dark before they capture the backdrop), so doing it
            // once up front makes every switch instant and flicker-free. Heavy
            // *work* (scans, sampling) is gated on `isActive`, not on mount, and
            // shows a loading state — so mounting stays cheap.
            //
            // Each tab keeps its own GlassEffectContainer: one container can't
            // wrap all tabs, because it composites every glass descendant into a
            // single layer that ignores the per-tab opacity, bleeding hidden
            // tabs through. Mounted-once already means each tab's glass is
            // created a single time and never re-initialized on switch.
            ZStack {
                DashboardView()
                    .tabVisibility(section == .dashboard)
                ProcessesView(model: processesModel, isActive: section == .processes)
                    .tabVisibility(section == .processes)
                AppsView(model: appsModel, isActive: section == .applications)
                    .tabVisibility(section == .applications)
                CleanupView(model: cleanupModel, isActive: section == .cleanup)
                    .tabVisibility(section == .cleanup)
                StorageView(model: storageModel, isActive: section == .storage)
                    .tabVisibility(section == .storage)
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

private extension View {
    /// A kept-mounted tab: visible and interactive only when active, otherwise
    /// hidden (but still laid out, so it never has to re-mount).
    func tabVisibility(_ active: Bool) -> some View {
        opacity(active ? 1 : 0)
            .allowsHitTesting(active)
            .accessibilityHidden(!active)
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

    /// The dashboard's cards batched into one Liquid Glass pass. Kept per-view:
    /// the tab is mounted once, so this container is created once and never
    /// re-initialized on switch.
    @ViewBuilder
    private var glassBatched: some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *), settings.glassEnabled {
            GlassEffectContainer { cards }
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
