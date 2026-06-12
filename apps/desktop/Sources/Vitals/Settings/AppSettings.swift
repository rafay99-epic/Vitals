import SwiftUI
import Combine
import AppKit
import ServiceManagement

enum TemperatureUnit: String, CaseIterable, Identifiable {
    case celsius, fahrenheit
    var id: String { rawValue }
    var symbol: String { self == .celsius ? "°C" : "°F" }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

enum MenuBarMode: String, CaseIterable, Identifiable {
    case average, hottest, fan, iconOnly
    var id: String { rawValue }

    var label: String {
        switch self {
        case .average: return "Average CPU temperature"
        case .hottest: return "Hottest core"
        case .fan: return "Fan speed"
        case .iconOnly: return "Icon only"
        }
    }
}

/// User preferences, persisted to UserDefaults.
@MainActor
final class AppSettings: ObservableObject {
    @Published var refreshInterval: Double { didSet { defaults.set(refreshInterval, forKey: "refreshInterval") } }
    @Published var unit: TemperatureUnit { didSet { defaults.set(unit.rawValue, forKey: "temperatureUnit") } }
    @Published var historyMinutes: Int { didSet { defaults.set(historyMinutes, forKey: "historyMinutes") } }
    @Published var menuBarMode: MenuBarMode { didSet { defaults.set(menuBarMode.rawValue, forKey: "menuBarMode") } }
    @Published var warnThreshold: Double { didSet { defaults.set(warnThreshold, forKey: "warnThreshold") } }
    @Published var notifyOverheat: Bool { didSet { defaults.set(notifyOverheat, forKey: "notifyOverheat") } }
    @Published var notifyThermal: Bool { didSet { defaults.set(notifyThermal, forKey: "notifyThermal") } }
    @Published var loggingEnabled: Bool { didSet { defaults.set(loggingEnabled, forKey: "loggingEnabled") } }
    @Published var autoUpdateCheck: Bool { didSet { defaults.set(autoUpdateCheck, forKey: "autoUpdateCheck") } }
    @Published var liquidGlass: Bool { didSet { defaults.set(liquidGlass, forKey: "liquidGlass") } }

    @Published var theme: AppTheme {
        didSet {
            defaults.set(theme.rawValue, forKey: "theme")
            applyTheme()
        }
    }

    @Published var showMenuBar: Bool {
        didSet {
            defaults.set(showMenuBar, forKey: "showMenuBar")
            // Never let the app become unreachable: no menu bar item means
            // the Dock icon must stay.
            if !showMenuBar { hideDockIcon = false }
        }
    }

    @Published var hideDockIcon: Bool {
        didSet {
            defaults.set(hideDockIcon, forKey: "hideDockIcon")
            applyActivationPolicy()
        }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            guard !syncingLoginItem else { return }
            updateLoginItem()
        }
    }
    @Published private(set) var loginItemError: String?

    private let defaults: UserDefaults
    private var syncingLoginItem = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            "refreshInterval": 2.0,
            "temperatureUnit": TemperatureUnit.celsius.rawValue,
            "historyMinutes": 10,
            "showMenuBar": true,
            "menuBarMode": MenuBarMode.average.rawValue,
            "warnThreshold": 85.0,
            "notifyOverheat": true,
            "notifyThermal": true,
            "loggingEnabled": true,
            "autoUpdateCheck": true,
            "liquidGlass": true,
            "theme": AppTheme.system.rawValue,
            "hideDockIcon": false,
        ])

        refreshInterval = defaults.double(forKey: "refreshInterval")
        unit = TemperatureUnit(rawValue: defaults.string(forKey: "temperatureUnit") ?? "") ?? .celsius
        historyMinutes = defaults.integer(forKey: "historyMinutes")
        showMenuBar = defaults.bool(forKey: "showMenuBar")
        menuBarMode = MenuBarMode(rawValue: defaults.string(forKey: "menuBarMode") ?? "") ?? .average
        warnThreshold = defaults.double(forKey: "warnThreshold")
        notifyOverheat = defaults.bool(forKey: "notifyOverheat")
        notifyThermal = defaults.bool(forKey: "notifyThermal")
        loggingEnabled = defaults.bool(forKey: "loggingEnabled")
        autoUpdateCheck = defaults.bool(forKey: "autoUpdateCheck")
        liquidGlass = defaults.bool(forKey: "liquidGlass")
        theme = AppTheme(rawValue: defaults.string(forKey: "theme") ?? "") ?? .system
        hideDockIcon = defaults.bool(forKey: "hideDockIcon")

        // SMAppService.status is an XPC round-trip; in init it sat directly
        // on the launch path and delayed the first frame. Load it async.
        launchAtLogin = false
        syncingLoginItem = true
        Task { [weak self] in
            let enabled = await Task.detached { SMAppService.mainApp.status == .enabled }.value
            guard let self else { return }
            self.launchAtLogin = enabled
            self.syncingLoginItem = false
        }
    }

    // MARK: Temperature formatting

    /// Converts a sensor reading (always stored in °C) to the display unit.
    func display(_ celsius: Double) -> Double {
        unit == .fahrenheit ? celsius * 9 / 5 + 32 : celsius
    }

    /// "45.1°" in the display unit.
    func format(_ celsius: Double, decimals: Int = 1) -> String {
        String(format: "%.\(decimals)f°", display(celsius))
    }

    /// "45.1 °C" / "113.2 °F".
    func formatWithUnit(_ celsius: Double, decimals: Int = 1) -> String {
        String(format: "%.\(decimals)f %@", display(celsius), unit.symbol)
    }

    // MARK: System integration

    func applyActivationPolicy() {
        NSApplication.shared.setActivationPolicy(hideDockIcon ? .accessory : .regular)
    }

    func applyTheme() {
        NSApplication.shared.appearance = theme.nsAppearance
    }

    private func updateLoginItem() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginItemError = nil
        } catch {
            loginItemError = error.localizedDescription
            syncingLoginItem = true
            launchAtLogin = SMAppService.mainApp.status == .enabled
            syncingLoginItem = false
        }
    }
}
