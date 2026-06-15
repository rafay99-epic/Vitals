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

/// A live reading the menu-bar item can show next to the icon. Any number can
/// be enabled at once; an empty set means "icon only".
enum MenuBarMetric: String, CaseIterable, Identifiable {
    case cpuTemp, cpuUsage, gpuUsage, memory, fan
    var id: String { rawValue }

    /// Label shown in the Settings picker.
    var label: String {
        switch self {
        case .cpuTemp:  return "CPU temperature"
        case .cpuUsage: return "CPU usage"
        case .gpuUsage: return "GPU usage"
        case .memory:   return "Memory used"
        case .fan:      return "Fan speed"
        }
    }

    /// SF Symbol shown before the value — matches the dashboard subsystems.
    var symbol: String {
        switch self {
        case .cpuTemp:  return "thermometer.medium"
        case .cpuUsage: return "cpu"
        case .gpuUsage: return "cpu.fill"
        case .memory:   return "memorychip"
        case .fan:      return "fan"
        }
    }

    /// Compact word used in the menu bar's Text style (in place of the symbol).
    var shortLabel: String {
        switch self {
        case .cpuTemp:  return "Temp"
        case .cpuUsage: return "CPU"
        case .gpuUsage: return "GPU"
        case .memory:   return "RAM"
        case .fan:      return "Fan"
        }
    }
}

/// User preferences, persisted to UserDefaults.
@MainActor
final class AppSettings: ObservableObject {
    @Published var refreshInterval: Double { didSet { defaults.set(refreshInterval, forKey: "refreshInterval") } }
    @Published var unit: TemperatureUnit { didSet { defaults.set(unit.rawValue, forKey: "temperatureUnit") } }
    @Published var historyMinutes: Int { didSet { defaults.set(historyMinutes, forKey: "historyMinutes") } }
    /// Stored as a comma-joined list of raw values ("" = icon only).
    @Published var menuBarMetrics: Set<MenuBarMetric> {
        didSet {
            defaults.set(MenuBarMetric.allCases.filter(menuBarMetrics.contains).map(\.rawValue).joined(separator: ","),
                         forKey: "menuBarMetrics")
        }
    }
    /// Icon style (SF Symbol + value) vs. plain text style (short word + value).
    @Published var menuBarUseIcons: Bool { didSet { defaults.set(menuBarUseIcons, forKey: "menuBarUseIcons") } }
    /// Gently animate the menu-bar icons (fan spins, the rest breathe). Costs a
    /// few redraws a second while shown; ignored in Text style.
    @Published var menuBarAnimated: Bool { didSet { defaults.set(menuBarAnimated, forKey: "menuBarAnimated") } }
    @Published var warnThreshold: Double { didSet { defaults.set(warnThreshold, forKey: "warnThreshold") } }
    @Published var notifyOverheat: Bool { didSet { defaults.set(notifyOverheat, forKey: "notifyOverheat") } }
    @Published var notifyThermal: Bool { didSet { defaults.set(notifyThermal, forKey: "notifyThermal") } }
    @Published var loggingEnabled: Bool { didSet { defaults.set(loggingEnabled, forKey: "loggingEnabled") } }
    @Published var autoUpdateCheck: Bool { didSet { defaults.set(autoUpdateCheck, forKey: "autoUpdateCheck") } }
    /// Master switch for GPU-driven rendering: Liquid Glass and every animation.
    /// On by default, but turning it off drops the app to opaque classic cards
    /// with no motion — Activity-Monitor-light on the GPU. Liquid Glass requires
    /// this to be on (see `glassEnabled`).
    @Published var gpuAcceleration: Bool { didSet { defaults.set(gpuAcceleration, forKey: "gpuAcceleration") } }
    /// Opt-in (defaults off): the translucent Liquid Glass look. Costs real GPU,
    /// so the app ships lean and the user turns this on deliberately.
    @Published var liquidGlass: Bool { didSet { defaults.set(liquidGlass, forKey: "liquidGlass") } }
    /// Whether Liquid Glass should actually render. Requires the user opt-in,
    /// GPU acceleration, and real hardware: without a hardware GPU (VMs,
    /// paravirtual/headless hosts) software-rendered backdrop blurs grow into the
    /// gigabytes (see `Hardware.supportsLiquidGlass`). The stored preferences are
    /// left untouched, so glass returns automatically when conditions allow.
    var glassEnabled: Bool { liquidGlass && gpuAcceleration && Hardware.supportsLiquidGlass }

    /// True while Vitals is the focused app. Drives the background freeze: when
    /// the user switches away, continuous animations stop (numbers stay live).
    @Published private(set) var appActive: Bool = NSApp?.isActive ?? true

    /// The single flag every view consults before animating. Off when GPU
    /// acceleration is disabled or the app isn't focused.
    var animationsEnabled: Bool { gpuAcceleration && appActive }
    /// 0 = clearest window backdrop, 1 = most frosted.
    @Published var glassIntensity: Double { didSet { defaults.set(glassIntensity, forKey: "glassIntensity") } }
    /// Whether opening the Storage tab kicks off the disk-walking analysis on
    /// its own. Off by default — the scan is the heaviest work in the app, so
    /// it waits for an explicit Analyze press unless the user opts in.
    @Published var autoAnalyzeStorage: Bool { didSet { defaults.set(autoAnalyzeStorage, forKey: "autoAnalyzeStorage") } }
    /// Whether the Storage analyzer counts dotfiles and hidden folders.
    @Published var analyzerIncludesHidden: Bool { didSet { defaults.set(analyzerIncludesHidden, forKey: "analyzerIncludesHidden") } }
    /// Unlocks the "Scan whole disk" action in Storage. Off by default — it
    /// walks system areas from the volume root and can take a while; the UI
    /// still confirms each time before running it.
    @Published var allowWholeDiskScan: Bool { didSet { defaults.set(allowWholeDiskScan, forKey: "allowWholeDiskScan") } }
    /// Whether opening the Cleanup tab measures reclaimable junk on its own.
    /// Off by default — the scan waits for an explicit press. Cleaning always
    /// requires selection + confirmation regardless.
    @Published var autoScanCleanup: Bool { didSet { defaults.set(autoScanCleanup, forKey: "autoScanCleanup") } }
    /// Whether desktop widgets react to their readings — a rim glow that breathes
    /// with severity and a fan icon that spins at a speed proportional to real
    /// RPM. On by default; turn it off for perfectly still panels.
    @Published var animateWidgets: Bool { didSet { defaults.set(animateWidgets, forKey: "animateWidgets") } }

    // MARK: Processes
    /// Fold an app's helper processes under the app (Brave's 18 helpers → one
    /// "Brave" row). On by default; off lists every process separately.
    @Published var groupHelperProcesses: Bool { didSet { defaults.set(groupHelperProcesses, forKey: "groupHelperProcesses") } }
    /// Show system/root-owned processes too. Off by default — those can't be
    /// quit without admin rights and are mostly noise.
    @Published var showSystemProcesses: Bool { didSet { defaults.set(showSystemProcesses, forKey: "showSystemProcesses") } }
    /// Ask before a normal Quit. Off by default so quitting is one click; Force
    /// Quit always confirms regardless.
    @Published var confirmBeforeQuittingProcess: Bool { didSet { defaults.set(confirmBeforeQuittingProcess, forKey: "confirmBeforeQuittingProcess") } }

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
    private var activeObservers: [NSObjectProtocol] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            "refreshInterval": 2.0,
            "temperatureUnit": TemperatureUnit.celsius.rawValue,
            "historyMinutes": 10,
            "showMenuBar": true,
            "menuBarUseIcons": true,
            "menuBarAnimated": true,
            "warnThreshold": 85.0,
            "notifyOverheat": true,
            "notifyThermal": true,
            "loggingEnabled": true,
            "autoUpdateCheck": true,
            "gpuAcceleration": true,
            // Ships off: the app is lean (opaque cards) by default; glass is opt-in.
            "liquidGlass": false,
            "glassIntensity": 0.15,
            "theme": AppTheme.system.rawValue,
            "hideDockIcon": false,
            "autoAnalyzeStorage": false,
            "analyzerIncludesHidden": true,
            "allowWholeDiskScan": false,
            "autoScanCleanup": false,
            "animateWidgets": true,
            "groupHelperProcesses": true,
            "showSystemProcesses": false,
            "confirmBeforeQuittingProcess": false,
        ])

        refreshInterval = defaults.double(forKey: "refreshInterval")
        unit = TemperatureUnit(rawValue: defaults.string(forKey: "temperatureUnit") ?? "") ?? .celsius
        historyMinutes = defaults.integer(forKey: "historyMinutes")
        showMenuBar = defaults.bool(forKey: "showMenuBar")
        menuBarMetrics = AppSettings.loadMenuBarMetrics(defaults)
        menuBarUseIcons = defaults.bool(forKey: "menuBarUseIcons")
        menuBarAnimated = defaults.bool(forKey: "menuBarAnimated")
        warnThreshold = defaults.double(forKey: "warnThreshold")
        notifyOverheat = defaults.bool(forKey: "notifyOverheat")
        notifyThermal = defaults.bool(forKey: "notifyThermal")
        loggingEnabled = defaults.bool(forKey: "loggingEnabled")
        autoUpdateCheck = defaults.bool(forKey: "autoUpdateCheck")
        gpuAcceleration = defaults.bool(forKey: "gpuAcceleration")
        liquidGlass = defaults.bool(forKey: "liquidGlass")
        glassIntensity = defaults.double(forKey: "glassIntensity")
        theme = AppTheme(rawValue: defaults.string(forKey: "theme") ?? "") ?? .system
        hideDockIcon = defaults.bool(forKey: "hideDockIcon")
        autoAnalyzeStorage = defaults.bool(forKey: "autoAnalyzeStorage")
        analyzerIncludesHidden = defaults.bool(forKey: "analyzerIncludesHidden")
        allowWholeDiskScan = defaults.bool(forKey: "allowWholeDiskScan")
        autoScanCleanup = defaults.bool(forKey: "autoScanCleanup")
        animateWidgets = defaults.bool(forKey: "animateWidgets")
        groupHelperProcesses = defaults.bool(forKey: "groupHelperProcesses")
        showSystemProcesses = defaults.bool(forKey: "showSystemProcesses")
        confirmBeforeQuittingProcess = defaults.bool(forKey: "confirmBeforeQuittingProcess")

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

        // Freeze animations when Vitals isn't the focused app: observe app
        // activation and republish `appActive`. The model keeps sampling, so
        // numbers stay live — only motion stops. Registered last: the closures
        // capture self, which must be fully initialized first.
        let center = NotificationCenter.default
        activeObservers = [
            center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.appActive = true }
            },
            center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.appActive = false }
            },
        ]
    }

    deinit {
        activeObservers.forEach(NotificationCenter.default.removeObserver)
    }

    // MARK: Temperature formatting

    /// Converts a sensor reading (always stored in °C) to the display unit.
    func display(_ celsius: Double) -> Double {
        unit == .fahrenheit ? celsius * 9 / 5 + 32 : celsius
    }

    /// Reads the menu-bar metric set, migrating the pre-v0.20 single `menuBarMode`
    /// key (average/hottest → CPU temperature, fan → fan, iconOnly → none).
    private static func loadMenuBarMetrics(_ defaults: UserDefaults) -> Set<MenuBarMetric> {
        if let raw = defaults.string(forKey: "menuBarMetrics") {
            // An empty string is a deliberate "icon only" choice, not absence.
            return Set(raw.split(separator: ",").compactMap { MenuBarMetric(rawValue: String($0)) })
        }
        switch defaults.string(forKey: "menuBarMode") {
        case "fan":      return [.fan]
        case "iconOnly": return []
        default:         return [.cpuTemp]
        }
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
