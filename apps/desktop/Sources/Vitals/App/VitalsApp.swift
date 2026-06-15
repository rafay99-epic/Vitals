import SwiftUI
import AppKit

struct VitalsApp: App {
    @StateObject private var settings: AppSettings
    @StateObject private var model: VitalsModel
    @StateObject private var updater: Updater
    @StateObject private var fanControl: FanController
    @StateObject private var widgets: WidgetManager

    init() {
        let settings = AppSettings()
        let model = VitalsModel(settings: settings)
        let updater = Updater()
        model.start()
        updater.startAutomaticChecks(settings: settings)
        settings.applyActivationPolicy()
        settings.applyTheme()
        _settings = StateObject(wrappedValue: settings)
        _model = StateObject(wrappedValue: model)
        _updater = StateObject(wrappedValue: updater)
        _fanControl = StateObject(wrappedValue: FanController())
        // Widgets observe the same model/settings — one data path, no re-polling.
        _widgets = StateObject(wrappedValue: WidgetManager(model: model, settings: settings))
    }

    var body: some Scene {
        // Window (not WindowGroup): exactly one main window, like Activity
        // Monitor — no ⌘N duplicates, dock clicks and openWindow always
        // return the existing one.
        Window("Vitals", id: "main") {
            ContentView()
                .environmentObject(model)
                .environmentObject(settings)
                .environmentObject(updater)
                .environmentObject(fanControl)
                .environment(\.animationsEnabled, settings.animationsEnabled)
        }
        .defaultSize(width: 1100, height: 760)
        // No system title bar: ContentView's header carries branding, tabs,
        // and window dragging. Traffic lights overlay the header's leading
        // edge (it pads around them).
        .windowStyle(.hiddenTitleBar)
        .commands {
            SettingsCommands()
            HelpCommands()
        }

        // A plain window instead of the Settings scene: SettingsLink/openSettings
        // is unreliable in apps that also have a MenuBarExtra, openWindow is not.
        Window("Vitals Settings", id: "settings") {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(updater)
                .environmentObject(widgets)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Window("Vitals Help", id: "help") {
            HelpView()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        MenuBarExtra(isInserted: menuBarInserted) {
            MenuBarPanel()
                .environmentObject(model)
                .environmentObject(settings)
                .environmentObject(fanControl)
                .environment(\.animationsEnabled, settings.animationsEnabled)
        } label: {
            menuBarLabel
        }
        .menuBarExtraStyle(.window)
    }

    /// SwiftUI writes back to `isInserted` on every scene evaluation. Binding
    /// straight to the @Published property republishes even for same-value
    /// writes, which re-invalidates the scene — an infinite render loop that
    /// pegs the main thread. Only forward real changes.
    private var menuBarInserted: Binding<Bool> {
        Binding(
            get: { settings.showMenuBar },
            set: { newValue in
                if settings.showMenuBar != newValue {
                    settings.showMenuBar = newValue
                }
            }
        )
    }

    @ViewBuilder
    private var menuBarLabel: some View {
        let warning = model.averageCPUTemp.map { $0 >= settings.warnThreshold } ?? false
        // allCases keeps a stable left-to-right order regardless of toggle order.
        let metrics = MenuBarMetric.allCases.filter(settings.menuBarMetrics.contains)
        if metrics.isEmpty {
            Image(systemName: warning ? "flame.fill" : "thermometer.medium")
        } else if let image = menuBarImage(metrics, warning: warning) {
            // MenuBarExtra renders a multi-view label as only its first element,
            // and bridging a Text to the status title strips inline SF Symbols —
            // so the icon+value row is rendered to one template image instead.
            Image(nsImage: image)
        } else {
            // Fallback if rendering ever fails: values only, no per-metric icons.
            Text(metrics.map(menuBarValue).joined(separator: "  "))
        }
    }

    /// Renders the selected metrics — each an SF Symbol plus its live value — to
    /// a single template image. Template so macOS tints it for the menu bar
    /// (white on dark, dimmed when inactive), exactly like a native item.
    @MainActor
    private func menuBarImage(_ metrics: [MenuBarMetric], warning: Bool) -> NSImage? {
        let row = HStack(spacing: 6) {
            ForEach(metrics) { metric in
                // The CPU-temperature metric flips to a flame when hot — the
                // same overheat cue the icon-only mode shows.
                Label(menuBarValue(metric),
                      systemImage: metric == .cpuTemp && warning ? "flame.fill" : metric.symbol)
                    .labelStyle(.titleAndIcon)
            }
        }
        .font(.system(size: 12, weight: .regular))
        .foregroundStyle(.black) // shape only; the template tints it

        let renderer = ImageRenderer(content: row)
        renderer.scale = 2 // the menu bar is rendered @2x on every modern Mac
        guard let image = renderer.nsImage else { return nil }
        image.isTemplate = true
        return image
    }

    /// The live reading shown for one metric. A dash (never a fabricated value)
    /// stands in when a subsystem isn't present or hasn't reported yet.
    private func menuBarValue(_ metric: MenuBarMetric) -> String {
        switch metric {
        case .cpuTemp:  return model.averageCPUTemp.map { settings.format($0, decimals: 0) } ?? "–"
        case .cpuUsage: return "\(Int(model.cpuUsage.rounded()))%"
        case .gpuUsage: return model.gpu?.utilization.map { "\(Int($0.rounded()))%" } ?? "–"
        case .memory:   return model.memory.map { String(format: "%.1fG", Double($0.used) / 1_073_741_824) } ?? "–"
        case .fan:      return model.fans.first.map { "\(Int($0.rpm))" } ?? "–"
        }
    }
}

/// Replaces the default "Settings…" item in the app menu so ⌘, opens our
/// settings window.
struct SettingsCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                openWindow(id: "settings")
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }
}

/// Points the Help menu at the in-app help window.
struct HelpCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("Vitals Help") {
                openWindow(id: "help")
            }
            .keyboardShortcut("?", modifiers: .command)
        }
    }
}

