import SwiftUI
import AppKit

struct VitalsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    // SwiftUI creates the App once, so these live for the process.
    private let settings: AppSettings
    private let model: VitalsModel
    private let updater: Updater
    private let navigator: Navigator
    private let menuBar: MenuBarController

    init() {
        // Create the data home before logging starts.
        DataHome.prepare()
        // Arm crash capture before anything else can fault.
        CrashReporter.install()
        let settings = AppSettings()
        let model = VitalsModel(settings: settings)
        let updater = Updater()
        let navigator = Navigator()
        model.start()
        updater.startAutomaticChecks(settings: settings)
        settings.applyActivationPolicy()
        settings.applyTheme()
        self.settings = settings
        self.model = model
        self.updater = updater
        self.navigator = navigator
        menuBar = MenuBarController(model: model, settings: settings, navigator: navigator)
        Log.notice(.app, "Vitals \(Updater.currentVersion) launched (\(Channel.current.rawValue))")
        Task.detached(priority: .utility) {
            // Surface a crash / unclean exit from the previous run, off the launch path.
            CrashReporter.reportPreviousRunIfNeeded()
            FanHelperRetirement.releaseFans()
        }
    }

    var body: some Scene {
        // Window, not WindowGroup: one main window, no ⌘N duplicates.
        Window("Vitals", id: "main") {
            ContentView()
                .environment(model)
                .environment(settings)
                .environment(updater)
                .environment(navigator)
        }
        .defaultSize(width: 1100, height: 760)
        // No system title bar: the sidebar carries branding and window dragging.
        .windowStyle(.hiddenTitleBar)
        .commands {
            SettingsCommands(navigator: navigator)
            CommandGroup(replacing: .help) {}
        }
    }
}

/// ⌘, selects the in-window Settings section, reopening the window if closed.
struct SettingsCommands: Commands {
    let navigator: Navigator
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                navigator.section = .settings
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }
}
