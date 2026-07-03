import SwiftUI

/// Every navigable destination, as one flat tier in the sidebar — a glanceable
/// Overview on top, then a read-only **Monitor** group and a write/maintenance
/// **Maintain** group (the "read freely, write carefully" split, made visible).
/// This replaces the old two-tier navigation (top capsule tabs *plus* the
/// System/Applications sub-segment bars): one level, no tabs-in-tabs.
enum NavSection: String, CaseIterable, Identifiable {
    case overview
    case cpu, gpu, memory, battery, network, sensors, processes, history
    case storage, cleanup, applications, loginItems
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview:     return "Overview"
        case .cpu:          return "CPU"
        case .gpu:          return "GPU"
        case .memory:       return "Memory"
        case .battery:      return "Battery"
        case .network:      return "Network"
        case .sensors:      return "Temps & Fans"
        case .processes:    return "Processes"
        case .history:      return "History"
        case .storage:      return "Storage"
        case .cleanup:      return "Cleanup"
        case .applications: return "Applications"
        case .loginItems:   return "Login Items"
        case .settings:     return "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .overview:     return "gauge.with.dots.needle.50percent"
        case .cpu:          return "cpu"
        case .gpu:          return "cpu.fill"
        case .memory:       return "memorychip"
        case .battery:      return "battery.100percent"
        case .network:      return "network"
        case .sensors:      return "thermometer.medium"
        case .processes:    return "list.bullet"
        case .history:      return "chart.xyaxis.line"
        case .storage:      return "internaldrive"
        case .cleanup:      return "sparkles"
        case .applications: return "square.grid.2x2"
        case .loginItems:   return "power"
        case .settings:     return "gearshape"
        }
    }

}

/// Top-level navigation: a fixed left sidebar over one content canvas. The
/// sidebar never collapses, so window geometry never changes from navigation
/// (the constraint the old capsule-tab shell solved by forbidding a sidebar
/// outright — a *fixed* rail honours it too, while giving one clean nav level).
struct ContentView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var model: VitalsModel
    /// The selected destination, shared app-wide so the ⌘, command and the
    /// menu-bar gear can also land on the Settings section (now an in-window
    /// panel, not a separate dialog).
    @EnvironmentObject private var navigator: Navigator
    /// Sections opened at least once, kept mounted for instant switch-back —
    /// seeded with Overview so home is live at launch. Mirrors the old lazy-tab
    /// approach: a section joins on first selection; hidden ones stay laid out.
    @State private var visited: Set<NavSection> = [.overview]

    /// The current section, read/written through the shared navigator.
    private var section: NavSection { navigator.section }

    // Per-section models, owned here so a scan started in one section survives
    // switching sections (Processes, Apps, Login Items, Cleanup, Storage).
    @StateObject private var processesModel = ProcessesModel()
    @StateObject private var appsModel = AppsModel()
    @StateObject private var loginItemsModel = LoginItemsModel()
    @StateObject private var cleanupModel = CleanupModel()
    @StateObject private var storageModel = StorageModel()

    // Network sits right after Battery — a conscious, approved consequence:
    // adding an 8th Monitor row pushes Storage past the ⌘1…⌘9 window, so it
    // loses its ⌘9 shortcut (the `row` shortcut assignment is purely positional).
    private static let monitor: [NavSection] = [.cpu, .gpu, .memory, .battery, .network, .sensors, .processes, .history]
    private static let maintain: [NavSection] = [.storage, .cleanup, .applications, .loginItems]

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().opacity(0.5)
            content
        }
        .ignoresSafeArea(edges: .top)
        .modifier(WindowBackdrop())
        .frame(minWidth: 980, minHeight: 680)
        .onAppear { model.setMainWindowVisible(true) }
        .onDisappear { model.setMainWindowVisible(false) }
        // Keep the kept-mounted set in sync when navigation comes from outside
        // the sidebar (⌘,, the menu-bar gear) — and on first appear, so a window
        // reopened straight onto Settings mounts it. `initial: true` covers both.
        .onChange(of: navigator.section, initial: true) { _, new in visited.insert(new) }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            sidebarHeader
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    row(.overview, shortcutIndex: 0)
                    groupLabel("Monitor")
                    ForEach(Array(Self.monitor.enumerated()), id: \.element) { index, item in
                        row(item, shortcutIndex: index + 1)
                    }
                    groupLabel("Maintain")
                    ForEach(Array(Self.maintain.enumerated()), id: \.element) { index, item in
                        // Continue the running index so the 9th visible row
                        // (Storage) keeps ⌘9; the row's `< 9` guard drops the rest.
                        row(item, shortcutIndex: 1 + Self.monitor.count + index)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
            // Settings is pinned to the very bottom — always visible regardless of
            // how far the section list scrolls, the way macOS apps anchor app-wide
            // settings (Music, Sensei). It's its own group, not part of Monitor or
            // Maintain.
            Divider().opacity(0.4).padding(.horizontal, 8)
            VStack(alignment: .leading, spacing: 1) {
                row(.settings, shortcutIndex: nil)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
        .frame(width: 212)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        // No system title bar, so the sidebar drags the window (its top strip
        // shares the row with the traffic lights).
        .gesture(WindowDragGesture())
    }

    /// Branding + the app-wide update affordance. The top inset clears the
    /// traffic lights. (Settings moved into the sidebar's pinned bottom row.)
    private var sidebarHeader: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 24, height: 24)
            Text("Vitals").font(.system(size: 14, weight: .semibold))
            Spacer()
            HeaderUpdateButton()
        }
        .padding(.horizontal, 12)
        .padding(.top, 38)
        .padding(.bottom, 10)
    }

    private func groupLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 9)
            .padding(.top, 14)
            .padding(.bottom, 3)
    }

    /// A sidebar destination row — icon + label, the whole row a click target,
    /// the selected one filled. ⌘1…⌘9 follow visible position for the first
    /// nine. Switching never animates geometry — only the selection fill moves.
    private func row(_ item: NavSection, shortcutIndex: Int?) -> some View {
        let selected = section == item
        let shortcut = shortcutIndex.flatMap { $0 < 9 ? KeyEquivalent(Character("\($0 + 1)")) : nil }
        return Button {
            visited.insert(item)
            navigator.section = item
        } label: {
            HStack(spacing: 9) {
                Image(systemName: item.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .frame(width: 20)
                Text(item.title)
                    .font(.system(size: 13, weight: selected ? .medium : .regular))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(selected ? AnyShapeStyle(.quaternary) : AnyShapeStyle(Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(selected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        .keyboardShortcut(shortcut.map { KeyboardShortcut($0, modifiers: .command) })
        .help(item.title)
    }

    // MARK: Content

    /// A section is active only when it's the selected one (the gate every
    /// kept-alive chart / sampler reads). The window-open gate is separate
    /// (`model.setMainWindowVisible`), so this is just the selection.
    private func active(_ s: NavSection) -> Bool { section == s }

    /// Sections mount lazily, then stay alive (kept-mounted, hidden) so switching
    /// back is instant. Switches aren't animated — fading a translucent panel in
    /// over the glass window flashes dark before the blur resolves.
    private var content: some View {
        ZStack {
            if visited.contains(.overview) {
                DashboardView(isActive: active(.overview), drill: drill).tabVisibility(active(.overview))
            }
            if visited.contains(.cpu) { CPUView().tabVisibility(active(.cpu)) }
            if visited.contains(.gpu) { GPUView(isActive: active(.gpu)).tabVisibility(active(.gpu)) }
            if visited.contains(.memory) { MemoryView(isActive: active(.memory)).tabVisibility(active(.memory)) }
            if visited.contains(.battery) { BatteryView(isActive: active(.battery)).tabVisibility(active(.battery)) }
            if visited.contains(.network) { NetworkView(isActive: active(.network)).tabVisibility(active(.network)) }
            if visited.contains(.sensors) { SensorsView().tabVisibility(active(.sensors)) }
            if visited.contains(.processes) {
                ProcessesView(model: processesModel, isActive: active(.processes)).tabVisibility(active(.processes))
            }
            if visited.contains(.history) { HistoryView(isActive: active(.history)).tabVisibility(active(.history)) }
            if visited.contains(.storage) {
                StorageView(model: storageModel, isActive: active(.storage)).tabVisibility(active(.storage))
            }
            if visited.contains(.cleanup) {
                CleanupView(model: cleanupModel, isActive: active(.cleanup)).tabVisibility(active(.cleanup))
            }
            if visited.contains(.applications) {
                AppsView(model: appsModel, isActive: active(.applications)).tabVisibility(active(.applications))
            }
            if visited.contains(.loginItems) {
                LoginItemsView(model: loginItemsModel, isActive: active(.loginItems)).tabVisibility(active(.loginItems))
            }
            if visited.contains(.settings) {
                SettingsView(isActive: active(.settings)).tabVisibility(active(.settings))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(nil, value: section)
    }

    /// Drill from a Dashboard tile straight into the matching Monitor section.
    private func drill(to target: NavSection) {
        visited.insert(target)
        navigator.section = target
    }
}

/// The header's update affordance: a compact badged download icon when an
/// update is available (one click installs, from any section), and a small
/// spinner while it downloads and installs. Reads the shared `Updater`, so it
/// stays in sync. Nothing shows when up to date.
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
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(.blue.opacity(hovered ? 0.22 : 0.14)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.12)) { hovered = hovering }
            }
            .help("Install \(Channel.current.displayName) \(release.displayVersion)")
        case .readyToInstall(let release):
            Button {
                Task { await updater.installPending() }
            } label: {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 15, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.green)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(.green.opacity(hovered ? 0.22 : 0.14)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.12)) { hovered = hovering }
            }
            .help("Install \(Channel.current.displayName) \(release.displayVersion) — downloaded and ready")
        case .downloading:
            spinner.help("Downloading update…")
        case .installing:
            spinner.help("Installing — Vitals will relaunch in a moment")
        default:
            EmptyView()
        }
    }

    private var spinner: some View {
        ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 26, height: 26)
    }
}

extension View {
    /// A kept-mounted section: visible and interactive only when active,
    /// otherwise hidden (but still laid out, so it never has to re-mount).
    func tabVisibility(_ active: Bool) -> some View {
        opacity(active ? 1 : 0)
            .allowsHitTesting(active)
            .accessibilityHidden(!active)
    }
}

/// The Dashboard: the glanceable overview, Mole-style. A health-score hero, a
/// bento grid of per-subsystem tiles (each with a live sparkline, each a tap into
/// the matching Monitor section), the live multi-metric chart, power and fans, and
/// the top processes. Detail is a drill-in — the heavy per-subsystem cards live in
/// the Monitor sections now, so nothing here is duplicated.
struct DashboardView: View {
    @EnvironmentObject private var model: VitalsModel
    @EnvironmentObject private var settings: AppSettings
    /// True only while the Dashboard is the visible section. The live history
    /// chart rebuilds its marks from `chartHistory` on every tick — gating it
    /// (and the hover lookup) on `isActive` keeps a kept-alive background
    /// dashboard from paying that cost every sample, mirroring GPU/Battery.
    let isActive: Bool
    /// Jump to a Monitor section (tap a tile to drill into its detail).
    let drill: (NavSection) -> Void

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
    /// the section is mounted once, so this container is created once and never
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
            DashboardHealthHero(drill: drill)
            DashboardTileGrid(drill: drill)
            PerformanceHistoryCard(isActive: isActive)
            HStack(alignment: .top, spacing: 16) {
                PowerCard()
                FanCard()
            }
            DashboardProcessesCard(drill: drill)
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
            if settings.isOnBattery {
                Text("on battery")
                Text("·")
            }
            Text("Updates every \(settings.effectiveRefreshInterval, format: .number) s")
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
                Label("Vitals \(release.displayVersion) is available", systemImage: "arrow.down.circle.fill")
                    .foregroundStyle(.blue)
                Text("You're on \(Updater.currentVersion)")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Install Update") {
                    Task { await updater.downloadAndInstall() }
                }
                .buttonStyle(.borderedProminent)
            }
        case .readyToInstall(let release):
            banner {
                Label("Vitals \(release.displayVersion) is ready to install", systemImage: "arrow.down.circle.fill")
                    .foregroundStyle(.green)
                Text("Downloaded in the background")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Install & Relaunch") {
                    Task { await updater.installPending() }
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
