import SwiftUI

/// Top-level navigation: a stationary header with segmented tabs over one
/// fixed content canvas — Activity Monitor style. There is no sidebar and no
/// window toolbar, so nothing can resize or snap the content, ever: tab
/// switches change what's drawn, never the geometry it's drawn in.
struct ContentView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var model: VitalsModel
    @State private var section: AppTab = .dashboard
    @State private var gearHovered = false
    @Environment(\.openWindow) private var openWindow
    @Namespace private var tabIndicator
    // Owned here so the scans survive section switches.
    @StateObject private var processesModel = ProcessesModel()
    @StateObject private var appsModel = AppsModel()
    @StateObject private var loginItemsModel = LoginItemsModel()
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
                GPUView(isActive: section == .gpu)
                    .tabVisibility(section == .gpu)
                BatteryView(isActive: section == .battery)
                    .tabVisibility(section == .battery)
                HealthView()
                    .tabVisibility(section == .health)
                DiskView()
                    .tabVisibility(section == .disk)
                HistoryView(isActive: section == .history)
                    .tabVisibility(section == .history)
                ProcessesView(model: processesModel, isActive: section == .processes)
                    .tabVisibility(section == .processes)
                AppsView(model: appsModel, isActive: section == .applications)
                    .tabVisibility(section == .applications)
                LoginItemsView(model: loginItemsModel, isActive: section == .loginItems)
                    .tabVisibility(section == .loginItems)
                CleanupView(model: cleanupModel, isActive: section == .cleanup)
                    .tabVisibility(section == .cleanup)
                StorageView(model: storageModel, isActive: section == .storage)
                    .tabVisibility(section == .storage)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Swap tabs instantly — never cross-fade. Fading a translucent tab
            // in over the translucent glass window shows a dark intermediate
            // before the blur resolves (the "dark then frost" flash). Snapping
            // composites the incoming tab correctly in one frame. The tab
            // indicator still springs — it lives in the header, unaffected.
            .animation(nil, value: section)
        }
        // The hidden title bar still reserves a safe-area strip; claim it so
        // the header shares the row with the traffic lights instead of
        // leaving a dead band above itself.
        .ignoresSafeArea(edges: .top)
        .modifier(WindowBackdrop())
        .frame(minWidth: minWindowWidth, minHeight: 680)
        // Let the model skip the costly top-process sweep when the window is
        // closed (menu-bar only).
        .onAppear { model.setMainWindowVisible(true) }
        .onDisappear { model.setMainWindowVisible(false) }
        // If the user hides the tab they're on, fall back to the Dashboard so
        // the canvas never shows a tab with no indicator in the bar.
        .onChange(of: settings.hiddenTabs) { _, hidden in
            if hidden.contains(section) { section = .dashboard }
        }
    }

    /// "Labels" mode shows every tab name, so the centered bar needs a wider
    /// floor to stay clear of the wordmark — more so at the larger size. The
    /// icon-led modes always fit at 980.
    private var minWindowWidth: CGFloat {
        guard settings.tabDisplayMode == .labels else { return 980 }
        return settings.tabSize == .large ? 1200 : 1100
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
                // App-wide update affordance — visible on every tab, not just
                // the Dashboard banner, so an available update is never missed.
                HeaderUpdateButton()
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
        .frame(height: settings.tabSize.headerHeight)
        .contentShape(Rectangle())
        .gesture(WindowDragGesture())
    }

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(Array(settings.visibleTabs.enumerated()), id: \.element) { index, item in
                tabButton(item, index: index)
            }
        }
        .padding(3)
        .background(Capsule().fill(.quaternary.opacity(0.45)))
    }

    /// Whether this tab shows its text label, per the display-mode setting:
    /// Labels → always, Icons → never, Expanding → only when selected.
    private func showsLabel(for item: AppTab, selected: Bool) -> Bool {
        switch settings.tabDisplayMode {
        case .labels: return true
        case .icons: return false
        case .expanding: return selected
        }
    }

    /// A capsule tab whose label appears per the display mode and whose metrics
    /// scale with the size setting. In Expanding mode only the selected tab
    /// reveals its label (riding the same spring as the sliding indicator, so it
    /// grows out of the icon); the rest stay icon-only with the name on hover /
    /// for VoiceOver. The ⌘ shortcut follows visible position, so ⌘1 is always
    /// the leftmost tab.
    private func tabButton(_ item: AppTab, index: Int) -> some View {
        let selected = section == item
        let size = settings.tabSize
        let showLabel = showsLabel(for: item, selected: selected)
        let shortcut = index < 9 ? KeyEquivalent(Character("\(index + 1)")) : nil
        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                section = item
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: item.symbol)
                    .font(.system(size: size.iconSize, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: size.iconSlot)  // stable slot so icons don't shift as labels grow
                if showLabel {
                    Text(item.title)
                        .font(.system(size: size.labelSize, weight: .medium))
                        .fixedSize()
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, showLabel ? size.hPadSelected : size.hPadCollapsed)
            .padding(.vertical, size.vPad)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(selected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        .background {
            if selected {
                Capsule()
                    .fill(.quaternary)
                    .matchedGeometryEffect(id: "selected-tab", in: tabIndicator)
            }
        }
        .keyboardShortcut(shortcut.map { KeyboardShortcut($0, modifiers: .command) })
        .accessibilityLabel(item.title)
        .help(shortcut != nil ? "\(item.title) (⌘\(index + 1))" : item.title)
    }
}

/// The header's update affordance: a compact badged download icon when an
/// update is available (one click installs, from any tab), and a small spinner
/// while it downloads and installs. Icon-only so the header stays uncrowded with
/// eight tabs — the full "Install Update" call to action still lives in the
/// Dashboard banner. Reads the shared `Updater`, so it stays in sync. Nothing
/// shows when up to date.
private struct HeaderUpdateButton: View {
    @EnvironmentObject private var updater: Updater
    @State private var hovered = false

    var body: some View {
        switch updater.status {
        case .available(let release):
            Button {
                Task { await updater.downloadAndInstall() }
            } label: {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 15, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.blue)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(.blue.opacity(hovered ? 0.22 : 0.14)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.12)) { hovered = hovering }
            }
            .help("Install \(Channel.current.displayName) \(release.displayVersion)")
        case .downloading:
            spinner.help("Downloading update…")
        case .installing:
            spinner.help("Installing — Vitals will relaunch in a moment")
        default:
            EmptyView()
        }
    }

    private var spinner: some View {
        ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 30, height: 30)
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
            PowerCard()
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
            CollapsibleCard(
                title: "SSD",
                symbol: DiskContent.symbol(for: model.diskHealth),
                subtitle: model.diskHealth.map { "\($0.percentUsed)% used" }
            ) {
                DiskContent()
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
