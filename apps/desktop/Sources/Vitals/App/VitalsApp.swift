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
        let symbol = warning ? "flame.fill" : "thermometer.medium"
        switch settings.menuBarMode {
        case .iconOnly:
            Image(systemName: symbol)
        case .average:
            Label(model.averageCPUTemp.map { settings.format($0, decimals: 0) } ?? "–", systemImage: symbol)
                .labelStyle(.titleAndIcon)
        case .hottest:
            Label(model.hottestCPUSensor.map { settings.format($0.celsius, decimals: 0) } ?? "–", systemImage: symbol)
                .labelStyle(.titleAndIcon)
        case .fan:
            Label(model.fans.first.map { "\(Int($0.rpm))" } ?? "–", systemImage: "fan")
                .labelStyle(.titleAndIcon)
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

