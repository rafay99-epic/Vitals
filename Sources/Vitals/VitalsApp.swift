import SwiftUI
import AppKit

@main
enum Main {
    static func main() {
        if CommandLine.arguments.contains("--probe") {
            runProbe()
        } else if CommandLine.arguments.contains("--check-update") {
            runUpdateCheck()
        } else {
            VitalsApp.main()
        }
    }
}

struct VitalsApp: App {
    @StateObject private var settings: AppSettings
    @StateObject private var model: VitalsModel
    @StateObject private var updater: Updater

    init() {
        let settings = AppSettings()
        let model = VitalsModel(settings: settings)
        let updater = Updater()
        model.start()
        updater.startAutomaticChecks(settings: settings)
        settings.applyActivationPolicy()
        _settings = StateObject(wrappedValue: settings)
        _model = StateObject(wrappedValue: model)
        _updater = StateObject(wrappedValue: updater)
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(model)
                .environmentObject(settings)
                .environmentObject(updater)
        }
        .defaultSize(width: 880, height: 760)
        .commands {
            SettingsCommands()
        }

        // A plain window instead of the Settings scene: SettingsLink/openSettings
        // is unreliable in apps that also have a MenuBarExtra, openWindow is not.
        Window("Vitals Settings", id: "settings") {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(updater)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        MenuBarExtra(isInserted: menuBarInserted) {
            MenuBarContent()
                .environmentObject(model)
                .environmentObject(settings)
        } label: {
            menuBarLabel
        }
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

struct MenuBarContent: View {
    @EnvironmentObject private var model: VitalsModel
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let average = model.averageCPUTemp {
            Text("CPU average  \(settings.formatWithUnit(average))")
        }
        if let hottest = model.hottestCPUSensor {
            Text("Hottest core  \(settings.formatWithUnit(hottest.celsius)) (\(hottest.label))")
        }
        if let fan = model.fans.first {
            Text("Fan  \(Int(fan.rpm)) rpm")
        }
        Text(String(format: "CPU usage  %.0f%%", model.cpuUsage))
        Text("Thermal pressure  \(model.thermalState.label)")
        Divider()
        Button("Open Vitals") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Settings…") {
            openWindow(id: "settings")
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut(",")
        Divider()
        Button("Quit Vitals") {
            NSApp.terminate(nil)
        }
    }
}

/// `Vitals --check-update` queries GitHub Releases once and prints the
/// verdict — handy for testing the update pipeline without the GUI.
private func runUpdateCheck() {
    let semaphore = DispatchSemaphore(value: 0)
    Task {
        do {
            if let release = try await Updater.fetchLatestRelease() {
                print("Latest release: \(release.version) (\(release.assetName))")
                print("This build:     \(Updater.currentVersion)")
                print(Updater.isVersion(release.version, newerThan: Updater.currentVersion)
                    ? "→ update available"
                    : "→ up to date")
            } else {
                print("No releases published yet.")
            }
        } catch {
            print("Check failed: \(error.localizedDescription)")
        }
        semaphore.signal()
    }
    semaphore.wait()
}

/// `Vitals --probe` prints one round of raw readings to stdout and exits.
/// Useful for sanity-checking the sensors without launching the GUI.
private func runProbe() {
    print("== Vitals probe ==")
    print(HardwareInfo.chipName, "·", HardwareInfo.osVersion)

    let readings = HIDSensors().readAll()
    print("\n\(readings.count) temperature sensors:")
    for reading in readings.sorted(by: { $0.name < $1.name }) {
        print(String(format: "  %-36s %6.2f °C", (reading.name as NSString).utf8String!, reading.celsius))
    }

    if let smc = SMC() {
        let fans = smc.fans()
        print("\n\(fans.count) fans:")
        for fan in fans {
            print("  Fan \(fan.id): \(Int(fan.rpm)) rpm (target \(Int(fan.targetRPM)), range \(Int(fan.minRPM))–\(Int(fan.maxRPM)))")
        }
    } else {
        print("\nSMC: connection failed")
    }

    if let used = MemoryStats.usedBytes() {
        print(String(format: "\nMemory: %.1f / %.0f GB", gigabytes(used), gigabytes(ProcessInfo.processInfo.physicalMemory)))
    }

    if let battery = Battery.read() {
        print(String(
            format: "\nBattery: %.0f%%, health %@, %@ cycles, %@",
            battery.percent,
            battery.healthPercent.map { String(format: "%.0f%%", $0) } ?? "n/a",
            battery.cycleCount.map(String.init) ?? "n/a",
            battery.isCharging ? "charging" : (battery.externalPower ? "on AC" : "on battery")
        ))
    } else {
        print("\nBattery: not found")
    }

    let processSampler = ProcessSampler()
    _ = processSampler.sample(top: 5)
    Thread.sleep(forTimeInterval: 1.0)
    print("\nTop processes:")
    for process in processSampler.sample(top: 5) {
        print(String(format: "  %-30s %5.1f%%", (process.name as NSString).utf8String!, process.cpuPercent))
    }
}
