import SwiftUI

/// Top-level navigation: a fixed left sidebar over one content canvas. The
/// sidebar never collapses, so window geometry never changes from navigation.
struct ContentView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(VitalsModel.self) private var model
    /// Shared app-wide so the ⌘, command and the menu-bar gear can also select
    /// the Settings section.
    @Environment(Navigator.self) private var navigator
    private var section: NavSection { navigator.section }

    // Per-section models, owned here so a scan started in one section survives
    // switching sections.
    @State private var appsModel = AppsModel()
    @State private var cleanupModel = CleanupModel()
    @State private var historyModel = HistoryModel()

    private static let monitor: [NavSection] = [.cpu, .gpu, .memory, .battery, .network, .sensors, .history]
    private static let maintain: [NavSection] = [.diskHealth, .cleanup, .applications]

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().opacity(0.5)
            content
        }
        .ignoresSafeArea(edges: .top)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.animationsEnabled, settings.appActive)
        .frame(minWidth: 980, minHeight: 680)
        .onAppear {
            model.setMainWindowVisible(true)
            model.setVisibleSection(section)
        }
        .onChange(of: section, initial: true) { _, newSection in
            model.setVisibleSection(newSection)
        }
        .onDisappear { model.setMainWindowVisible(false) }
        .background(WindowOcclusionReader { model.setMainWindowUnoccluded($0) })
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            sidebarHeader
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    row(.overview, shortcut: Self.shortcut(1))
                    groupLabel("Monitor")
                    ForEach(Array(Self.monitor.enumerated()), id: \.element) { index, item in
                        row(item, shortcut: Self.shortcut(index + 2))
                    }
                    groupLabel("Maintain")
                    ForEach(Array(Self.maintain.enumerated()), id: \.element) { index, item in
                        // Maintain gets its own ⌥⌘ tier so its shortcuts don't
                        // shift (or fall off the ⌘1–9 ladder) as Monitor grows.
                        row(item, shortcut: Self.shortcut(index + 1, modifiers: [.command, .option]))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
            // Settings is pinned to the bottom, outside the scrolling list, so it's
            // always visible.
            Divider().opacity(0.4).padding(.horizontal, 8)
            VStack(alignment: .leading, spacing: 1) {
                row(.settings, shortcut: nil)
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

    /// Branding + the update button. The top inset clears the traffic lights.
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

    /// ⌘n / ⌥⌘n for the nth row of a group. Digits only go to 9, so anything
    /// past that has no shortcut rather than a wrong one.
    private static func shortcut(_ n: Int, modifiers: EventModifiers = .command) -> KeyboardShortcut? {
        guard (1...9).contains(n) else { return nil }
        return KeyboardShortcut(KeyEquivalent(Character("\(n)")), modifiers: modifiers)
    }

    /// A sidebar row, the whole row a click target. Overview + Monitor take ⌘1-⌘8
    /// by position; Maintain has its own ⌥⌘1-⌥⌘3 tier. Only the selection fill
    /// changes on switch, never geometry.
    private func row(_ item: NavSection, shortcut: KeyboardShortcut?) -> some View {
        let selected = section == item
        return Button {
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
        .keyboardShortcut(shortcut)
        .help(item.title)
    }

    // MARK: Content

    /// Mount only the selected section so hidden charts and layout trees don't
    /// stay alive. The section models above preserve scan results and tasks.
    private var content: some View {
        Group {
            switch section {
            case .overview:
                DashboardView(drill: drill)
            case .cpu:
                CPUView()
            case .gpu:
                GPUView()
            case .memory:
                MemoryView()
            case .battery:
                BatteryView()
            case .network:
                NetworkView()
            case .sensors:
                SensorsView()
            case .history:
                HistoryView(model: historyModel)
            case .diskHealth:
                DiskHealthView()
            case .cleanup:
                CleanupView(model: cleanupModel)
            case .applications:
                AppsView(model: appsModel)
            case .settings:
                SettingsView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(nil, value: section)
    }

    /// Drill from a Dashboard tile straight into the matching Monitor section.
    private func drill(to target: NavSection) {
        navigator.section = target
    }
}

/// Reports whether the hosting window is actually visible (not minimized,
/// hidden, fully covered, or on another Space), now and on every change.
private struct WindowOcclusionReader: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> NSView { ReaderView(onChange: onChange) }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ReaderView: NSView {
        let onChange: (Bool) -> Void
        private var observer: NSObjectProtocol?

        init(onChange: @escaping (Bool) -> Void) {
            self.onChange = onChange
            super.init(frame: .zero)
        }
        @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

        deinit { observer.map(NotificationCenter.default.removeObserver) }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observer.map(NotificationCenter.default.removeObserver)
            observer = nil
            guard let window else { return }
            onChange(window.occlusionState.contains(.visible))
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
            ) { [weak self, weak window] _ in
                guard let window else { return }
                self?.onChange(window.occlusionState.contains(.visible))
            }
        }
    }
}

/// The sidebar header's update button: a download icon when an update is
/// available or downloaded (one click installs), a spinner while downloading or
/// installing, nothing when up to date.
private struct HeaderUpdateButton: View {
    @Environment(Updater.self) private var updater
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

/// The Overview: health hero, per-subsystem tiles (each drills into its Monitor
/// section), the multi-metric chart, power and fans, and top processes.
struct DashboardView: View {
    @Environment(VitalsModel.self) private var model
    @Environment(AppSettings.self) private var settings
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
                    cards
                }
            }
            .padding(20)
        }
    }

    /// Lazy so the first frame and each resize frame only lay out on-screen cards.
    private var cards: some View {
        LazyVStack(alignment: .leading, spacing: 16) {
            UpdateBanner()
            DashboardHealthHero(drill: drill)
            DashboardTileGrid(drill: drill)
            PerformanceHistoryCard()
            HStack(alignment: .top, spacing: 16) {
                PowerCard()
                FanCard()
            }
            DashboardProcessesCard()
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
            if model.sensorsStalled {
                Label("Sensors not responding, readings paused", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else {
                Text("Updates every \(settings.effectiveRefreshInterval, format: .number) s")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }
}

/// Shown at the top of the dashboard while an update is available or installing.
struct UpdateBanner: View {
    @Environment(Updater.self) private var updater

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
