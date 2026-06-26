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

/// How tab names appear in the main navigation bar.
enum TabDisplayMode: String, CaseIterable, Identifiable {
    /// Only the selected tab shows its label; the rest collapse to icons.
    case expanding
    /// Every tab shows its label (widest — hide tabs you don't use if it gets tight).
    case labels
    /// Icon-only for every tab; names show on hover and to VoiceOver.
    case icons

    var id: String { rawValue }

    var label: String {
        switch self {
        case .expanding: return "Expanding"
        case .labels: return "Labels"
        case .icons: return "Icons"
        }
    }
}

/// Navigation-bar density. Mirrors System Settings' "Sidebar icon size":
/// scales the tab icon, label and the header it sits in, together.
enum TabSize: String, CaseIterable, Identifiable {
    case small, medium, large
    var id: String { rawValue }

    var label: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }

    var iconSize: CGFloat { switch self { case .small: 11; case .medium: 12; case .large: 13.5 } }
    var labelSize: CGFloat { switch self { case .small: 11.5; case .medium: 12; case .large: 13 } }
    var iconSlot: CGFloat { switch self { case .small: 15; case .medium: 16; case .large: 18 } }
    var hPadSelected: CGFloat { switch self { case .small: 10; case .medium: 12; case .large: 14 } }
    var hPadCollapsed: CGFloat { switch self { case .small: 7; case .medium: 8; case .large: 10 } }
    var vPad: CGFloat { switch self { case .small: 5; case .medium: 6; case .large: 7 } }
    var headerHeight: CGFloat { switch self { case .small: 42; case .medium: 46; case .large: 52 } }
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
    /// Reduce the sampling cadence while on battery (doubles the interval,
    /// capped at 5 s) and pause the menu-bar icon animation. On by default — a
    /// menu-bar monitor shouldn't burn the battery at the same cadence it keeps
    /// on AC. Low Power Mode floors the cadence at 10 s regardless of this toggle.
    @Published var reduceOnBattery: Bool { didSet { defaults.set(reduceOnBattery, forKey: "reduceOnBattery") } }
    /// Whether the Mac is currently on battery (vs. AC). Refreshed once per tick
    /// by `VitalsModel.updatePowerState`, so the cadence and the menu-bar
    /// animation gate react within one sample of a plug/unplug. Read-only
    /// outside this class; the testing seam is `_setPowerStateForTesting`.
    @Published private(set) var isOnBattery: Bool = PowerState.isOnBattery()
    /// Whether macOS' Low Power Mode is active. Same refresh path as
    /// `isOnBattery`; read straight from `ProcessInfo`.
    @Published private(set) var isLowPowerMode: Bool = ProcessInfo.processInfo.isLowPowerModeEnabled
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
    /// User-defined threshold alerts, stored as JSON. Separate from the tuned
    /// overheat/thermal built-ins above.
    @Published var alertRules: [AlertRule] {
        didSet {
            do {
                defaults.set(try JSONEncoder().encode(alertRules), forKey: "alertRules")
            } catch {
                Log.error(.settings, "couldn't encode alert rules — they won't persist", error: error)
            }
        }
    }
    @Published var loggingEnabled: Bool { didSet { defaults.set(loggingEnabled, forKey: "loggingEnabled") } }
    /// Developer/diagnostic logging floor — distinct from `loggingEnabled` (which
    /// is the user-facing metric history CSV). Drives `Log.minimumLevel`: `.off`
    /// captures nothing, `.notice` (default) captures meaningful events + errors,
    /// `.debug` is verbose. See `Log`.
    @Published var diagnosticLogLevel: LogLevel {
        didSet {
            defaults.set(diagnosticLogLevel.rawValue, forKey: "diagnosticLogLevel")
            Log.configure(minimumLevel: diagnosticLogLevel)
        }
    }
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
    /// The sampling interval actually in effect — the user's pick, adjusted for
    /// power state. AC: unchanged. Battery (with `reduceOnBattery`): doubled,
    /// capped at 5 s. Low Power Mode: floored at 10 s. Never below 0.5 s.
    /// History capacity still uses the base `refreshInterval`, so the chart's
    /// time span stays stable when the cadence throttles — only the density
    /// of points changes.
    var effectiveRefreshInterval: Double {
        PowerThrottle.interval(base: refreshInterval,
                               isOnBattery: isOnBattery,
                               isLowPowerMode: isLowPowerMode,
                               reduceOnBattery: reduceOnBattery)
    }
    /// Whether the menu-bar icon animation should run. The user opts in via
    /// `menuBarAnimated` (off by default — the status item isn't GPU-composited,
    /// so the animation rasterizes every frame on the CPU), and it needs GPU
    /// acceleration. On battery (with `reduceOnBattery`) or in Low Power Mode it
    /// pauses, mirroring macOS' own "reduce motion when saving power".
    var menuBarAnimationEnabled: Bool {
        menuBarAnimated && gpuAcceleration
            && !PowerThrottle.suppressAnimation(isOnBattery: isOnBattery,
                                                isLowPowerMode: isLowPowerMode,
                                                reduceOnBattery: reduceOnBattery)
    }
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

    // MARK: Navigation bar
    /// How tab labels appear (expanding / always / icon-only).
    @Published var tabDisplayMode: TabDisplayMode { didSet { defaults.set(tabDisplayMode.rawValue, forKey: "tabDisplayMode") } }
    /// Navigation-bar density.
    @Published var tabSize: TabSize { didSet { defaults.set(tabSize.rawValue, forKey: "tabSize") } }

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
    /// Where settings are mirrored for durability. nil disables the mirror —
    /// used by tests so they never touch the real `~/.vitals/config.json`.
    private let configURL: URL?
    private var syncingLoginItem = false
    private var activeObservers: [NSObjectProtocol] = []
    private var cancellables = Set<AnyCancellable>()

    /// The defaults registered at launch. Extracted to a static so `ConfigStore`
    /// can derive the full set of persisted keys from one source — no drift.
    static let registeredDefaults: [String: Any] = [
            "refreshInterval": 2.0,
            "temperatureUnit": TemperatureUnit.celsius.rawValue,
            "historyMinutes": 10,
            // On by default: a menu-bar monitor should sip battery, not drain it.
            // Doubles the sampling interval (capped at 5 s) on battery and pauses
            // the menu-bar icon animation; Low Power Mode slows to 10 s regardless.
            "reduceOnBattery": true,
            "showMenuBar": true,
            "menuBarUseIcons": true,
            // Off by default: a live status-item animation rasterizes every
            // frame on the CPU (~11% continuously, even backgrounded) since the
            // menu bar isn't GPU-composited like a window. Opt-in eye-candy; the
            // readout's numbers stay live regardless.
            "menuBarAnimated": false,
            "warnThreshold": 85.0,
            "notifyOverheat": true,
            "notifyThermal": true,
            // On by default: now that history lives in an efficient local SQLite
            // database (not a CSV), logging is cheap and reliable, so the History
            // tab is populated and useful out of the box. The data is local-only
            // (~/.vitals) and never leaves the Mac; it's one switch to turn off in
            // Settings → Data. A one-time enable (see `loggingDefaultedOnV2`) also
            // flips users who predate this default.
            "loggingEnabled": true,
            // Capture meaningful events + all errors out of the box (negligible
            // cost), but nothing chatty. The developer Log Console (a separate
            // window) views them; logging happens regardless.
            "diagnosticLogLevel": LogLevel.notice.rawValue,
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
            "tabDisplayMode": TabDisplayMode.expanding.rawValue,
            "tabSize": TabSize.medium.rawValue,
    ]

    /// Every UserDefaults key Vitals owns: the registered ones, plus those stored
    /// outside registration (the menu-bar metric set, the alert rules, and the
    /// one-time logging-default migration flag — which must persist so the flip
    /// runs only once). `ConfigStore` mirrors exactly these to `config.json`. A new
    /// setting is covered automatically if it has a registered default; otherwise
    /// add it here.
    static var persistedKeys: [String] {
        Array(registeredDefaults.keys) + ["menuBarMetrics", "alertRules", "loggingDefaultedOnV2"]
    }

    init(defaults: UserDefaults = .standard, configURL: URL? = ConfigStore.fileURL) {
        self.defaults = defaults
        self.configURL = configURL
        // Restore the durable config into UserDefaults before anything is read,
        // so settings survive a reinstall / cask upgrade that wiped the defaults.
        let restored = configURL.map { ConfigStore.restore(into: defaults, from: $0) } ?? 0
        defaults.register(defaults: Self.registeredDefaults)

        refreshInterval = defaults.double(forKey: "refreshInterval")
        unit = TemperatureUnit(rawValue: defaults.string(forKey: "temperatureUnit") ?? "") ?? .celsius
        historyMinutes = defaults.integer(forKey: "historyMinutes")
        reduceOnBattery = defaults.bool(forKey: "reduceOnBattery")
        showMenuBar = defaults.bool(forKey: "showMenuBar")
        menuBarMetrics = AppSettings.loadMenuBarMetrics(defaults)
        menuBarUseIcons = defaults.bool(forKey: "menuBarUseIcons")
        menuBarAnimated = defaults.bool(forKey: "menuBarAnimated")
        warnThreshold = defaults.double(forKey: "warnThreshold")
        notifyOverheat = defaults.bool(forKey: "notifyOverheat")
        notifyThermal = defaults.bool(forKey: "notifyThermal")
        alertRules = AppSettings.loadAlertRules(defaults)
        // History logging is now on by default (SQLite makes it cheap). A user who
        // installed before this — whose mirrored `loggingEnabled` is the old
        // `false`, overriding the new default on restore — is enabled once here,
        // marked by `loggingDefaultedOnV2` so it never re-overrides a later, explicit
        // choice to turn it back off.
        if defaults.object(forKey: "loggingDefaultedOnV2") == nil {
            defaults.set(true, forKey: "loggingEnabled")
            defaults.set(true, forKey: "loggingDefaultedOnV2")
        }
        loggingEnabled = defaults.bool(forKey: "loggingEnabled")
        diagnosticLogLevel = LogLevel(rawValue: defaults.integer(forKey: "diagnosticLogLevel")) ?? .notice
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
        tabDisplayMode = TabDisplayMode(rawValue: defaults.string(forKey: "tabDisplayMode") ?? "") ?? .expanding
        tabSize = TabSize(rawValue: defaults.string(forKey: "tabSize") ?? "") ?? .medium

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
            // On quit, flush any settings still inside the debounce window, so a
            // change made in the last second before quitting isn't lost.
            center.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.flushConfig() }
            },
        ]

        // didSet doesn't fire during init, so push the stored level into the
        // logger by hand — done last, once every stored property exists.
        Log.configure(minimumLevel: diagnosticLogLevel)
        if restored > 0 {
            Log.notice(.settings, "restored \(restored) settings from config.json")
        }

        // Mirror every change to the durable config file, debounced so a burst of
        // edits writes once. `save` skips unchanged content, so focus-driven
        // republishes (appActive) don't churn the file. Off-main: it's file I/O.
        objectWillChange
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] in self?.saveConfig() }
            .store(in: &cancellables)
        // Ensure the file exists from the first launch, even with no edits.
        saveConfig()
    }

    /// The bytes of the last config we wrote, so an unchanged save (e.g. the
    /// republish that fires on every window-focus change) is a cheap in-memory
    /// comparison rather than a disk read + write.
    private var lastConfigData: Data?

    /// Mirrors the current settings to `config.json` off the main thread, but
    /// only when the persisted content actually changed.
    private func saveConfig() {
        guard let configURL, let data = ConfigStore.serialize(defaults, keys: Self.persistedKeys),
              data != lastConfigData else { return }
        lastConfigData = data
        DispatchQueue.global(qos: .utility).async {
            ConfigStore.write(data, to: configURL)
        }
    }

    /// Writes the config synchronously — used on app termination so the last
    /// edits land even if they happened inside the save debounce window.
    private func flushConfig() {
        guard let configURL, let data = ConfigStore.serialize(defaults, keys: Self.persistedKeys),
              data != lastConfigData else { return }
        lastConfigData = data
        ConfigStore.write(data, to: configURL)
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

    /// Refreshes `isOnBattery` / `isLowPowerMode` from the system. Called once
    /// per tick by `VitalsModel`; only reassigns on a real transition so the
    /// model's restart-on-change sink doesn't fire every tick (a `@Published`
    /// property publishes on every assignment, even an unchanged one).
    func updatePowerState() {
        let onBattery = PowerState.isOnBattery()
        let lowPower = PowerState.isLowPowerMode()
        if isOnBattery != onBattery { isOnBattery = onBattery }
        if isLowPowerMode != lowPower { isLowPowerMode = lowPower }
    }

    /// Test seam to force a power state without touching IOKit/`ProcessInfo`.
    /// Underscored to signal it's not part of the app's API.
    func _setPowerStateForTesting(isOnBattery: Bool, isLowPowerMode: Bool) {
        self.isOnBattery = isOnBattery
        self.isLowPowerMode = isLowPowerMode
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

    private static func loadAlertRules(_ defaults: UserDefaults) -> [AlertRule] {
        guard let data = defaults.data(forKey: "alertRules") else { return [] }
        do {
            return try JSONDecoder().decode([AlertRule].self, from: data)
        } catch {
            Log.notice(.settings, "couldn't decode saved alert rules — resetting to none", error: error)
            return []
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
            Log.error(.settings, "login item \(launchAtLogin ? "register" : "unregister") failed", error: error)
            loginItemError = error.localizedDescription
            syncingLoginItem = true
            launchAtLogin = SMAppService.mainApp.status == .enabled
            syncingLoginItem = false
        }
    }
}
