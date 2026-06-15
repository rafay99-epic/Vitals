import SwiftUI
import AppKit

struct VitalsApp: App {
    // Keeps the app running when every window is closed, so the menu-bar item
    // (now a custom status item, not MenuBarExtra) stays put.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var settings: AppSettings
    @StateObject private var model: VitalsModel
    @StateObject private var updater: Updater
    @StateObject private var fanControl: FanController
    @StateObject private var widgets: WidgetManager
    @StateObject private var menuBar: MenuBarController

    init() {
        // Create the data home and migrate any legacy log before logging starts.
        DataHome.prepare()
        let settings = AppSettings()
        let model = VitalsModel(settings: settings)
        let updater = Updater()
        let fanControl = FanController()
        model.start()
        updater.startAutomaticChecks(settings: settings)
        settings.applyActivationPolicy()
        settings.applyTheme()
        _settings = StateObject(wrappedValue: settings)
        _model = StateObject(wrappedValue: model)
        _updater = StateObject(wrappedValue: updater)
        _fanControl = StateObject(wrappedValue: fanControl)
        // Widgets observe the same model/settings — one data path, no re-polling.
        _widgets = StateObject(wrappedValue: WidgetManager(model: model, settings: settings))
        // The menu-bar status item hosts a live, compositor-animated label.
        _menuBar = StateObject(wrappedValue: MenuBarController(model: model, settings: settings, fanControl: fanControl))
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

        // The menu-bar item is a custom NSStatusItem managed by `MenuBarController`
        // (created in init), not a MenuBarExtra scene — see that type for why.
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

