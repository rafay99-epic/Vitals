import SwiftUI

/// Top-level navigation: a fixed left sidebar over one content canvas. The
/// sidebar never collapses, so window geometry never changes from navigation.
struct ContentView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(VitalsModel.self) private var model
    /// Shared app-wide so the ⌘, command and the menu-bar gear can also select
    /// the Settings section.
    @Environment(Navigator.self) private var navigator
    @Environment(RemoteModel.self) private var remote
    @Environment(DevicesModel.self) private var phonePages
    private var section: NavSection { navigator.section }
    /// The phone `.device` shows: the picked one, else the first.
    private var shownDevice: String? { navigator.device ?? phonePages.phones.first?.id }

    // Per-section models, owned here so a scan started in one section survives
    // switching sections.
    @State private var appsModel = AppsModel()
    @State private var cleanupModel = CleanupModel()
    @State private var historyModel = HistoryModel()

    private static let monitor: [NavSection] = [.cpu, .gpu, .memory, .battery, .network, .sensors, .history]
    private static let maintain: [NavSection] = [.diskHealth, .cleanup, .applications, .remote]

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
                    if remote.isEnabled, !phonePages.phones.isEmpty {
                        groupLabel("Devices")
                        ForEach(phonePages.phones) { deviceRow($0) }
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
        navRow(title: item.title, symbol: item.symbol, selected: section == item, shortcut: shortcut) {
            navigator.section = item
        } trailing: {
            EmptyView()
        }
    }

    /// A phone's row: its page, with a dot for whether it answers right now.
    private func deviceRow(_ phone: PhoneDevice) -> some View {
        navRow(title: phone.name, symbol: DeviceLook.symbol(phone), selected: section == .device && shownDevice == phone.id, shortcut: nil) {
            navigator.device = phone.id
            navigator.section = .device
        } trailing: {
            OnlineDot(online: phone.online)
        }
    }

    private func navRow<Trailing: View>(
        title: String, symbol: String, selected: Bool, shortcut: KeyboardShortcut?,
        action: @escaping () -> Void, @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .frame(width: 20)
                Text(title)
                    .font(.system(size: 13, weight: selected ? .medium : .regular))
                    .lineLimit(1)
                Spacer(minLength: 0)
                trailing()
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
        .help(title)
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
            case .device:
                DevicePage(deviceId: shownDevice)
                    .id(shownDevice)
            case .diskHealth:
                DiskHealthView()
            case .cleanup:
                CleanupView(model: cleanupModel)
            case .applications:
                AppsView(model: appsModel)
            case .remote:
                RemoteView()
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
