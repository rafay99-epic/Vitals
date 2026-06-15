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
            MenuBarLabelView()
                .environmentObject(model)
                .environmentObject(settings)
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

}

/// The menu-bar status item's label. A standalone view (not an inline builder)
/// so it can own a small animation ticker that re-renders *only this item* —
/// the rest of the app never sees the per-frame updates. It also keeps the
/// label's body a plain Image/Text: MenuBarExtra bridges those to the status
/// item but renders nothing for a wrapper like TimelineView.
private struct MenuBarLabelView: View {
    @EnvironmentObject private var model: VitalsModel
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var animator = MenuBarAnimator()

    // allCases keeps a stable left-to-right order regardless of toggle order.
    private var metrics: [MenuBarMetric] {
        MenuBarMetric.allCases.filter(settings.menuBarMetrics.contains)
    }
    private var warning: Bool {
        model.averageCPUTemp.map { $0 >= settings.warnThreshold } ?? false
    }
    /// Animate only in icon style, when enabled and GPU rendering is on, and
    /// when there's actually an icon to move. Deliberately *not* gated on
    /// `animationsEnabled` — that freezes when Vitals is unfocused, but a
    /// menu-bar readout is meant to be watched from inside other apps.
    private var animate: Bool {
        settings.menuBarUseIcons && settings.menuBarAnimated
            && settings.gpuAcceleration && !metrics.isEmpty
    }

    var body: some View {
        label
            .task(id: animate) { animator.setRunning(animate) }
    }

    @ViewBuilder
    private var label: some View {
        if metrics.isEmpty {
            Image(systemName: warning ? "flame.fill" : "thermometer.medium")
        } else if !settings.menuBarUseIcons {
            // Text style: short word + value, rendered natively (crisp, no image).
            Text(menuBarText)
        } else {
            iconReadout(time: animate ? animator.phase : nil)
        }
    }

    /// Text-style readout, e.g. "Temp 57° · CPU 23% · RAM 12.8G".
    private var menuBarText: String {
        metrics.map { "\($0.shortLabel) \(menuBarValue($0))" }.joined(separator: " · ")
    }

    /// Icon-style readout as one template image, falling back to text if the
    /// render ever fails. MenuBarExtra renders a multi-view label as only its
    /// first element and strips inline SF Symbols from a bridged Text, so the
    /// whole icon+value row has to be drawn to an image.
    @ViewBuilder
    private func iconReadout(time: TimeInterval?) -> some View {
        if let image = menuBarImage(time: time) {
            Image(nsImage: image)
        } else {
            Text(menuBarText)
        }
    }

    /// Renders each metric's symbol + value to a single template image (so macOS
    /// tints it like a native item). When `time` is non-nil the icons animate at
    /// that instant: the fan spins (speed scales with rpm), the rest breathe.
    @MainActor
    private func menuBarImage(time: TimeInterval?) -> NSImage? {
        let fanFraction = fanSpinFraction
        let row = HStack(spacing: 6) {
            ForEach(Array(metrics.enumerated()), id: \.element) { index, metric in
                HStack(spacing: 3) {
                    animatedSymbol(metric: metric, index: index, time: time, fanFraction: fanFraction)
                    Text(menuBarValue(metric))
                }
            }
        }
        .font(.system(size: 12, weight: .regular))
        .foregroundStyle(.black)     // shape only; the template tints it
        .padding(2)                  // headroom so a spinning/breathing icon never clips

        let renderer = ImageRenderer(content: row)
        // Match the sharpest attached display instead of forcing @2x: on an
        // all-1x (non-Retina Intel) Mac this renders a quarter of the pixels,
        // while staying crisp on Retina.
        renderer.scale = NSScreen.screens.map(\.backingScaleFactor).max() ?? 2
        guard let image = renderer.nsImage else { return nil }
        image.isTemplate = true
        return image
    }

    /// One metric's symbol, animated when `time` is given. The CPU-temperature
    /// metric flips to a flame when hot — the same overheat cue icon-only shows.
    @ViewBuilder
    private func animatedSymbol(metric: MenuBarMetric, index: Int,
                                time: TimeInterval?, fanFraction: Double) -> some View {
        let image = Image(systemName: metric == .cpuTemp && warning ? "flame.fill" : metric.symbol)
        if let time {
            if metric == .fan {
                // Spin only while the fan turns; speed eases up with rpm.
                let degreesPerSecond = fanFraction > 0 ? 90 + 130 * fanFraction : 0
                image.rotationEffect(.degrees(time * degreesPerSecond))
            } else {
                // Slow, staggered breath so the icons don't pulse in lockstep.
                image.scaleEffect(1 + 0.07 * sin(2 * .pi * 0.45 * time + Double(index) * 0.9))
            }
        } else {
            image
        }
    }

    /// 0 when the fan is stopped (or unknown), rising toward 1 as it nears its
    /// rated maximum — drives how fast the menu-bar fan icon spins.
    private var fanSpinFraction: Double {
        guard let fan = model.fans.first, fan.rpm > 0 else { return 0 }
        let range = fan.maxRPM - fan.minRPM
        guard range > 0 else { return 0.5 } // spinning but no rated range → mid speed
        return min(max((fan.rpm - fan.minRPM) / range, 0), 1)
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

/// Drives the menu-bar icon animation: publishes a `phase` ~10×/second while
/// running, so only `MenuBarLabelView` re-renders. Uses `.common` run-loop mode
/// so it keeps ticking even while a menu is being tracked, and pauses whenever
/// the work would be wasted — display asleep or Low Power Mode — so a constantly
/// re-rendered status item never drains an idle or battery-saving Mac.
@MainActor
private final class MenuBarAnimator: ObservableObject {
    @Published private(set) var phase: TimeInterval = Date().timeIntervalSinceReferenceDate
    private var timer: Timer?
    private var wantsAnimation = false
    private var displayAsleep = false
    private var workspaceTokens: [NSObjectProtocol] = []
    private var defaultTokens: [NSObjectProtocol] = []

    /// 10 fps is plenty for a gentle spin/breath and lighter than a higher rate;
    /// the timer also runs with tolerance so the OS can batch the wake-ups.
    private static let interval: TimeInterval = 1.0 / 10.0

    init() {
        let workspace = NSWorkspace.shared.notificationCenter
        workspaceTokens.append(workspace.addObserver(forName: NSWorkspace.screensDidSleepNotification,
                                                     object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.displayAsleep = true; self?.sync() }
        })
        workspaceTokens.append(workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification,
                                                     object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.displayAsleep = false; self?.sync() }
        })
        defaultTokens.append(NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange,
                                                                    object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.sync() }
        })
    }

    deinit {
        let workspace = NSWorkspace.shared.notificationCenter
        workspaceTokens.forEach { workspace.removeObserver($0) }
        defaultTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }

    /// Called by the view as its `animate` condition flips.
    func setRunning(_ running: Bool) {
        wantsAnimation = running
        sync()
    }

    /// Animate only when the view wants it, the display is awake, and we aren't
    /// in Low Power Mode — animating an unseen or battery-saving menu bar is
    /// pure waste.
    private var shouldRun: Bool {
        wantsAnimation && !displayAsleep && !ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    private func sync() {
        if shouldRun {
            guard timer == nil else { return }
            let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.phase = Date().timeIntervalSinceReferenceDate }
            }
            timer.tolerance = Self.interval * 0.25
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        } else {
            timer?.invalidate()
            timer = nil
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

