import SwiftUI
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

/// A live reading the menu-bar item can show next to the icon. Any number can
/// be enabled at once; an empty set means "icon only".
enum MenuBarMetric: String, CaseIterable, Identifiable {
    case cpuTemp, cpuUsage, gpuUsage, memory, fan, network, disk
    var id: String { rawValue }

    var label: String {
        switch self {
        case .cpuTemp:  return "CPU temperature"
        case .cpuUsage: return "CPU usage"
        case .gpuUsage: return "GPU usage"
        case .memory:   return "Memory used"
        case .fan:      return "Fan speed"
        case .network:  return "Network download"
        case .disk:     return "Disk read"
        }
    }

    var symbol: String {
        switch self {
        case .cpuTemp:  return "thermometer.medium"
        case .cpuUsage: return "cpu"
        case .gpuUsage: return "cpu.fill"
        case .memory:   return "memorychip"
        case .fan:      return "fan"
        case .network:  return "network"
        case .disk:     return "internaldrive"
        }
    }

    /// Used in place of the symbol when `menuBarUseIcons` is off.
    var shortLabel: String {
        switch self {
        case .cpuTemp:  return "Temp"
        case .cpuUsage: return "CPU"
        case .gpuUsage: return "GPU"
        case .memory:   return "RAM"
        case .fan:      return "Fan"
        case .network:  return "Net"
        case .disk:     return "Disk"
        }
    }
}

/// User preferences, persisted to UserDefaults.
@MainActor
@Observable
final class AppSettings {
    var refreshInterval: Double { didSet { defaults.set(refreshInterval, forKey: "refreshInterval") } }
    var unit: TemperatureUnit { didSet { defaults.set(unit.rawValue, forKey: "temperatureUnit") } }
    var historyMinutes: Int { didSet { defaults.set(historyMinutes, forKey: "historyMinutes") } }
    /// Doubles the sampling interval on battery (capped at 5 s). Low Power Mode
    /// floors it at 10 s regardless. See `PowerThrottle`.
    var reduceOnBattery: Bool { didSet { defaults.set(reduceOnBattery, forKey: "reduceOnBattery") } }
    /// Refreshed once per tick by `updatePowerState`.
    private(set) var isOnBattery: Bool = PowerState.isOnBattery()
    private(set) var isLowPowerMode: Bool = ProcessInfo.processInfo.isLowPowerModeEnabled
    /// Stored as a comma-joined list of raw values ("" = icon only).
    var menuBarMetrics: Set<MenuBarMetric> {
        didSet {
            defaults.set(MenuBarMetric.allCases.filter(menuBarMetrics.contains).map(\.rawValue).joined(separator: ","),
                         forKey: "menuBarMetrics")
        }
    }
    var menuBarUseIcons: Bool { didSet { defaults.set(menuBarUseIcons, forKey: "menuBarUseIcons") } }
    var warnThreshold: Double { didSet { defaults.set(warnThreshold, forKey: "warnThreshold") } }
    var notifyOverheat: Bool { didSet { defaults.set(notifyOverheat, forKey: "notifyOverheat") } }
    var notifyThermal: Bool { didSet { defaults.set(notifyThermal, forKey: "notifyThermal") } }
    var loggingEnabled: Bool { didSet { defaults.set(loggingEnabled, forKey: "loggingEnabled") } }
    /// Diagnostic log floor (see `Log`), separate from `loggingEnabled`, which is
    /// the readings history.
    var diagnosticLogLevel: LogLevel {
        didSet {
            defaults.set(diagnosticLogLevel.rawValue, forKey: "diagnosticLogLevel")
            Log.configure(minimumLevel: diagnosticLogLevel)
        }
    }
    var autoUpdateCheck: Bool { didSet { defaults.set(autoUpdateCheck, forKey: "autoUpdateCheck") } }
    /// Pre-download a found update; installing still needs one tap.
    var autoDownloadUpdates: Bool { didSet { defaults.set(autoDownloadUpdates, forKey: "autoDownloadUpdates") } }
    /// True while Vitals is the focused app. View animations run only then.
    private(set) var appActive: Bool = NSApp?.isActive ?? true

    /// The user's interval adjusted for power state. History capacity uses the
    /// base `refreshInterval`, so a throttled chart keeps its span and gets sparser.
    var effectiveRefreshInterval: Double {
        PowerThrottle.interval(base: refreshInterval,
                               isOnBattery: isOnBattery,
                               isLowPowerMode: isLowPowerMode,
                               reduceOnBattery: reduceOnBattery)
    }
    /// Scan Cleanup on open. Cleaning always needs selection + confirmation.
    var autoScanCleanup: Bool { didSet { defaults.set(autoScanCleanup, forKey: "autoScanCleanup") } }
    var theme: AppTheme {
        didSet {
            defaults.set(theme.rawValue, forKey: "theme")
            applyTheme()
        }
    }

    var showMenuBar: Bool {
        didSet {
            defaults.set(showMenuBar, forKey: "showMenuBar")
            // No menu bar item means the Dock icon must stay, or the app is unreachable.
            if !showMenuBar { hideDockIcon = false }
        }
    }

    var hideDockIcon: Bool {
        didSet {
            defaults.set(hideDockIcon, forKey: "hideDockIcon")
            applyActivationPolicy()
        }
    }

    var launchAtLogin: Bool {
        didSet {
            guard !syncingLoginItem else { return }
            updateLoginItem()
        }
    }
    private(set) var loginItemError: String?

    private let defaults: UserDefaults
    @ObservationIgnored private var syncingLoginItem = false
    @ObservationIgnored private var activeObservers: [NSObjectProtocol] = []

    static let registeredDefaults: [String: Any] = [
            "refreshInterval": 2.0,
            "temperatureUnit": TemperatureUnit.celsius.rawValue,
            "historyMinutes": 10,
            "reduceOnBattery": true,
            "showMenuBar": true,
            "menuBarUseIcons": true,
            "warnThreshold": 85.0,
            "notifyOverheat": true,
            "notifyThermal": true,
            "loggingEnabled": true,
            "diagnosticLogLevel": LogLevel.notice.rawValue,
            "autoUpdateCheck": true,
            "autoDownloadUpdates": false,
            "theme": AppTheme.system.rawValue,
            "hideDockIcon": false,
            "autoScanCleanup": false,
    ]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: Self.registeredDefaults)

        refreshInterval = defaults.double(forKey: "refreshInterval")
        unit = TemperatureUnit(rawValue: defaults.string(forKey: "temperatureUnit") ?? "") ?? .celsius
        historyMinutes = defaults.integer(forKey: "historyMinutes")
        reduceOnBattery = defaults.bool(forKey: "reduceOnBattery")
        showMenuBar = defaults.bool(forKey: "showMenuBar")
        menuBarMetrics = AppSettings.loadMenuBarMetrics(defaults)
        menuBarUseIcons = defaults.bool(forKey: "menuBarUseIcons")
        warnThreshold = defaults.double(forKey: "warnThreshold")
        notifyOverheat = defaults.bool(forKey: "notifyOverheat")
        notifyThermal = defaults.bool(forKey: "notifyThermal")
        loggingEnabled = defaults.bool(forKey: "loggingEnabled")
        diagnosticLogLevel = LogLevel(rawValue: defaults.integer(forKey: "diagnosticLogLevel")) ?? .notice
        autoUpdateCheck = defaults.bool(forKey: "autoUpdateCheck")
        autoDownloadUpdates = defaults.bool(forKey: "autoDownloadUpdates")
        theme = AppTheme(rawValue: defaults.string(forKey: "theme") ?? "") ?? .system
        hideDockIcon = defaults.bool(forKey: "hideDockIcon")
        autoScanCleanup = defaults.bool(forKey: "autoScanCleanup")

        // SMAppService.status is an XPC round-trip; loaded async to keep it off the launch path.
        launchAtLogin = false
        syncingLoginItem = true
        Task { [weak self] in
            let enabled = await Task.detached { SMAppService.mainApp.status == .enabled }.value
            guard let self else { return }
            self.launchAtLogin = enabled
            self.syncingLoginItem = false
        }

        // Registered last: the closures capture self.
        let center = NotificationCenter.default
        activeObservers = [
            center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.appActive = true }
            },
            center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.appActive = false }
            },
        ]

        // didSet doesn't fire during init, so push the stored level by hand.
        Log.configure(minimumLevel: diagnosticLogLevel)
    }

    deinit {
        activeObservers.forEach(NotificationCenter.default.removeObserver)
    }

    // MARK: Temperature formatting

    /// Converts a sensor reading (always stored in °C) to the display unit.
    func display(_ celsius: Double) -> Double {
        unit == .fahrenheit ? celsius * 9 / 5 + 32 : celsius
    }

    // MARK: Power state

    /// Called once per tick. Writes only on a real transition, so observers of
    /// the cadence don't re-run every tick.
    func updatePowerState() {
        let onBattery = PowerState.isOnBattery()
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        if isOnBattery != onBattery { isOnBattery = onBattery }
        if isLowPowerMode != lowPower { isLowPowerMode = lowPower }
    }

    /// Test seam: forces a power state without touching IOKit/`ProcessInfo`.
    func _setPowerStateForTesting(isOnBattery: Bool, isLowPowerMode: Bool) {
        self.isOnBattery = isOnBattery
        self.isLowPowerMode = isLowPowerMode
    }

    /// Reads the menu-bar metric set. An empty string is a deliberate "icon only".
    private static func loadMenuBarMetrics(_ defaults: UserDefaults) -> Set<MenuBarMetric> {
        guard let raw = defaults.string(forKey: "menuBarMetrics") else { return [.cpuTemp] }
        return Set(raw.split(separator: ",").compactMap { MenuBarMetric(rawValue: String($0)) })
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
            Log.error(.settings, "login item \(launchAtLogin ? "register" : "unregister") failed", error: error)
            loginItemError = error.localizedDescription
            syncingLoginItem = true
            launchAtLogin = SMAppService.mainApp.status == .enabled
            syncingLoginItem = false
        }
    }
}
