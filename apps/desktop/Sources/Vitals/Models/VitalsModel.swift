import Foundation
import SwiftUI
import AppKit

@MainActor
@Observable
final class VitalsModel {
    struct Sensor: Identifiable {
        enum Kind { case cpu, gpu, storage, battery, other }
        let id: String
        let label: String
        let kind: Kind
        let celsius: Double
    }

    struct Sample: Identifiable {
        let id: Date
        let time: Date
        let averageCPU: Double
        let hottestCPU: Double
        let gpu: Double?
        let gpuUsage: Double?   // GPU busy %, nil when no GPU reading
        let usage: Double
        let memoryUsed: Double  // bytes
        let swapUsed: Double    // bytes
        let batteryPercent: Double?  // charge %, nil when no battery
        let totalWatts: Double?      // SoC package power, nil until the 2nd sample
        let batteryWatts: Double?    // signed: + charging, − draining; nil off battery
        let netInPerSec: Double?     // bytes/s, nil until the 2nd sample
        let netOutPerSec: Double?    // bytes/s, nil until the 2nd sample
        let diskReadPerSec: Double?  // bytes/s, nil until the 2nd sample
        let diskWritePerSec: Double? // bytes/s, nil until the 2nd sample
    }

    private(set) var cpuSensors: [Sensor] = []
    private(set) var gpuTemp: Double?
    /// GPU utilization and memory (nil when there's no readable GPU, e.g. a VM).
    private(set) var gpu: GPUSnapshot?
    private(set) var ssdTemp: Double?
    private(set) var batteryTemp: Double?
    private(set) var fans: [SMC.Fan] = []
    private(set) var hasSMC = false
    /// The full in-memory window. Views read `chartHistory`, never this.
    @ObservationIgnored private var history: [Sample] = []
    /// `history` thinned for drawing: charts can't show more points than
    /// pixels, and Swift Charts rebuild cost scales with mark count.
    private(set) var chartHistory: [Sample] = []
    private(set) var cpuUsage: Double = 0
    /// Per-cluster CPU utilisation (Apple Silicon). Nil without a trusted P/E split.
    private(set) var cpuClusters: (performance: Double, efficiency: Double)?
    /// Per-core utilisation. Empty without a trusted P/E split.
    private(set) var cpuPerCore: [CoreUsage] = []
    private(set) var memory: MemorySnapshot?
    /// VM page-traffic rates. Nil until the second sample: a rate needs a prior reading.
    private(set) var memoryActivity: MemoryActivity?
    private(set) var thermalState = ProcessInfo.processInfo.thermalState
    private(set) var topProcesses: [ProcessSampler.Process] = []
    /// Heaviest memory consumers, from the same sweep as the CPU-ordered `topProcesses`.
    private(set) var topMemoryProcesses: [ProcessSampler.Process] = []
    @ObservationIgnored private var previousMemorySnapshot: MemorySnapshot?
    @ObservationIgnored private var previousMemorySnapshotAt: Date?
    private(set) var battery: BatterySnapshot?
    /// Internal SSD SMART health. Nil when SMART isn't exposed, or for the first tick or two.
    private(set) var diskHealth: DiskHealthSnapshot?
    /// SoC power draw. Nil until the second sample (energy delta) and when
    /// IOReport is unavailable.
    private(set) var power: PowerSnapshot?
    /// Network throughput plus Wi-Fi link details. Nil until the second sample:
    /// the first reading has no prior byte counters.
    private(set) var network: NetworkSnapshot?
    @ObservationIgnored private var hasNetworkBaseline = false
    /// Disk read/write throughput. Nil until the second sample, like `network`.
    private(set) var diskIO: DiskIOSnapshot?
    @ObservationIgnored private var hasDiskIOBaseline = false
    /// False until the first sample lands; drives the loading state.
    private(set) var hasLoaded = false
    /// True while a sample is overdue (a sensor syscall wedged). The last
    /// readings stay on screen, and the Overview says they're paused.
    private(set) var sensorsStalled = false

    let memoryTotal = ProcessInfo.processInfo.physicalMemory

    /// True when a sample arrived with no usable readings at all, e.g. a VM.
    var sensorsUnavailable: Bool {
        hasLoaded && cpuSensors.isEmpty && gpuTemp == nil && !hasSMC && memory == nil
    }

    var averageCPUTemp: Double? {
        guard !cpuSensors.isEmpty else { return nil }
        return cpuSensors.map(\.celsius).reduce(0, +) / Double(cpuSensors.count)
    }

    var hottestCPUSensor: Sensor? {
        cpuSensors.max { $0.celsius < $1.celsius }
    }

    private let settings: AppSettings
    private let sampler = SensorSampler()
    private let notifications = NotificationManager()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var isSampling = false
    /// The one in-flight sample. Cancelling a Swift Task does not interrupt a
    /// blocking IOKit call, so the watchdog must not release this slot early.
    @ObservationIgnored private var samplingTask: Task<Void, Never>?
    @ObservationIgnored private var samplingStartedAt: Date?
    /// Window state that gates the heavy optional reads; see `windowOnScreen`.
    @ObservationIgnored private var mainWindowVisible = false
    @ObservationIgnored private var mainWindowUnoccluded = true
    /// Narrows optional reads to what the visible section needs.
    @ObservationIgnored private var visibleSection: NavSection = .overview
    /// Set by the sleep/wake observers. Also guards `start()` so a settings
    /// change made while asleep can't resume sampling before wake.
    @ObservationIgnored private var isAsleep = false
    @ObservationIgnored private var sleepObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var menuBarPanelVisible = false

    /// Call when the main window opens/closes (ContentView appear/disappear).
    func setMainWindowVisible(_ visible: Bool) {
        mainWindowVisible = visible
        publishChartsIfVisible()
    }

    /// Call when the main window becomes covered, minimized, hidden or moves
    /// to another Space (false), and when it's back in view (true).
    func setMainWindowUnoccluded(_ unoccluded: Bool) {
        mainWindowUnoccluded = unoccluded
        publishChartsIfVisible()
    }

    /// Call when the menu-bar dropdown opens/closes; its sparklines read charts.
    func setMenuBarPanelVisible(_ visible: Bool) {
        menuBarPanelVisible = visible
        publishChartsIfVisible()
    }

    /// Open and actually on screen: not minimized, hidden, fully covered, or on
    /// another Space.
    private var windowOnScreen: Bool { mainWindowVisible && mainWindowUnoccluded }

    /// Call when navigation changes so optional reads follow the visible section.
    func setVisibleSection(_ section: NavSection) { visibleSection = section }

    /// For tests: whether the sampling timer is armed.
    internal var isSamplingTimerActive: Bool { timer != nil }

    /// Optional reads needed this tick. GPU also feeds the GPU menu-bar metric
    /// and the dropdown's GPU row; the rest only matter with the window on screen.
    private var currentNeeds: SensorSampler.Needs {
        let section = windowOnScreen ? visibleSection : nil
        func showing(_ sections: NavSection...) -> Bool { section.map(sections.contains) ?? false }
        return SensorSampler.Needs(
            topProcesses: showing(.overview, .memory),
            gpu: showing(.overview, .gpu, .history)
                || menuBarPanelVisible
                || (settings.showMenuBar && settings.menuBarMetrics.contains(.gpuUsage)),
            power: showing(.overview, .cpu, .gpu, .battery, .history),
            networkDetails: showing(.overview, .network)
        )
    }
    private static let maxChartPoints = 300
    /// A sample overdue by this long counts as wedged. A real sample takes milliseconds.
    private static let sampleTimeout: TimeInterval = 5

    /// At most one history row per 10 s, however fast the tick.
    private static let logInterval: TimeInterval = 10
    @ObservationIgnored private var lastLoggedAt: Date = .distantPast

    @ObservationIgnored private var hotSince: Date?
    @ObservationIgnored private var lastHeatAlert: Date = .distantPast
    @ObservationIgnored private var previousThermalState = ProcessInfo.processInfo.thermalState
    private static let heatAlertAfter: TimeInterval = 120
    private static let heatAlertCooldown: TimeInterval = 600

    init(settings: AppSettings) {
        self.settings = settings
        observeChanges(of: { settings.effectiveRefreshInterval }) { [weak self] _ in self?.restartTimerIfAwake() }
        observeChanges(of: { settings.historyMinutes }) { [weak self] _ in self?.trimHistory() }
        // Ask for notification permission at launch when an alert is on, and
        // whenever one is turned on later.
        if settings.notifyOverheat || settings.notifyThermal { notifications.requestAuthorizationIfNeeded() }
        observeChanges(of: { settings.notifyOverheat || settings.notifyThermal }) { [weak self] enabled in
            if enabled { self?.notifications.requestAuthorizationIfNeeded() }
        }

        // Pause sampling across system sleep. Registered last: the closures
        // capture self, which must be fully initialized.
        let workspace = NSWorkspace.shared.notificationCenter
        sleepObservers = [
            workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.handleSleep() }
            },
            workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.handleWake() }
            },
        ]
    }

    deinit {
        timer?.invalidate()
        timer = nil
        samplingTask?.cancel()
        samplingTask = nil
        sleepObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
    }

    /// Floor of 0.5 s: a corrupted UserDefaults value of 0 would divide by zero below.
    private var safeRefreshInterval: Double { max(0.5, settings.refreshInterval) }

    private var maxHistory: Int {
        max(2, Int(Double(settings.historyMinutes) * 60.0 / safeRefreshInterval))
    }

    func start() {
        guard timer == nil, !isAsleep else { return }
        tick()
        let interval = settings.effectiveRefreshInterval
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer.tolerance = interval / 4
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func restartTimer() {
        timer?.invalidate()
        timer = nil
        start()
    }

    /// Restarts only while awake and already running. The `timer != nil` guard
    /// blocks a re-entrant call during the first `start()` (where `tick()` runs
    /// before `self.timer` is assigned) from leaking a second timer.
    private func restartTimerIfAwake() {
        guard !isAsleep, timer != nil else { return }
        restartTimer()
    }

    /// An in-flight tick may finish; no new ticks fire until `handleWake`.
    private func handleSleep() {
        guard !isAsleep else { return }
        isAsleep = true
        timer?.invalidate()
        timer = nil
        Log.notice(.sampler, "system sleeping — sampling paused")
    }

    /// Samples at once and re-reads the cadence, so a power-source change made
    /// during sleep takes effect immediately.
    private func handleWake() {
        guard isAsleep else { return }
        isAsleep = false
        Log.notice(.sampler, "system woke — sampling resumed")
        start()
    }

    private func trimHistory() {
        if history.count > maxHistory {
            history.removeFirst(history.count - maxHistory)
        }
        publishChartsIfVisible()
    }

    /// Charts cost ~60 MB of transient GPU memory per redraw, and a covered or
    /// minimized window still redraws. So `chartHistory` only moves while a chart
    /// can be seen; `history` keeps recording, and the next reveal catches up.
    private func publishChartsIfVisible() {
        guard windowOnScreen || menuBarPanelVisible else { return }
        chartHistory = history.thinned(to: Self.maxChartPoints)
    }

    /// One sample at a time: a tick that finds the previous one running is dropped.
    /// A wedged sensor syscall can't be cancelled, so an overdue sample flags
    /// readings stale but keeps the slot until it returns, rather than stacking
    /// blocked tasks.
    private func tick() {
        guard !isAsleep else { return }
        if isSampling {
            if let started = samplingStartedAt, !sensorsStalled,
               Date().timeIntervalSince(started) >= Self.sampleTimeout {
                samplingTask?.cancel()
                Log.notice(.sampler, "a sensor sample exceeded \(Self.sampleTimeout)s and was cancelled; readings paused")
                sensorsStalled = true
            }
            return
        }
        isSampling = true
        samplingStartedAt = Date()
        // May restart the timer and re-enter `tick`; `isSampling` makes that a no-op.
        settings.updatePowerState()

        let needs = currentNeeds
        samplingTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.isSampling = false
                self.samplingTask = nil
            }
            let snapshot = await self.sampler.sample(needs)
            guard !Task.isCancelled else { return }
            self.apply(snapshot, sampled: needs)
            self.assignIfChanged(&self.sensorsStalled, to: false)
        }
    }

    private func apply(_ snapshot: SensorSampler.Snapshot, sampled: SensorSampler.Needs) {
        let classified = snapshot.sensors
        cpuSensors = classified.filter { $0.kind == .cpu }
        assignIfChanged(&gpuTemp, to: Self.average(of: classified, kind: .gpu))
        assignIfChanged(&ssdTemp, to: Self.average(of: classified, kind: .storage))
        assignIfChanged(&batteryTemp, to: Self.average(of: classified, kind: .battery))
        fans = snapshot.fans
        assignIfChanged(&hasSMC, to: snapshot.hasSMC)
        assignIfChanged(&thermalState, to: ProcessInfo.processInfo.thermalState)
        if let usage = snapshot.cpuUsage {
            cpuUsage = usage.overall
            if let performance = usage.performance, let efficiency = usage.efficiency {
                cpuClusters = (performance: performance, efficiency: efficiency)
            } else {
                cpuClusters = nil
            }
            cpuPerCore = usage.perCore
        }
        memory = snapshot.memory
        updateMemoryActivity(snapshot.memory)
        topProcesses = snapshot.topProcesses
        topMemoryProcesses = snapshot.topMemoryProcesses
        battery = snapshot.battery
        diskHealth = snapshot.diskHealth
        updateNetwork(snapshot.network)
        updateDiskIO(snapshot.diskIO)
        // A read taken this tick replaces the value, nil included (a stalled or
        // missing sensor); a skipped read holds the last one for display. History
        // below logs only fresh readings, so a skip is a gap, not a stale value.
        if sampled.gpu { gpu = snapshot.gpu }
        if sampled.power { power = snapshot.power }
        assignIfChanged(&hasLoaded, to: true)

        let freshGPU = sampled.gpu ? snapshot.gpu : nil
        if let average = averageCPUTemp, let hottest = hottestCPUSensor {
            history.append(Sample(
                id: Date(),
                time: Date(),
                averageCPU: average,
                hottestCPU: hottest.celsius,
                gpu: gpuTemp,
                gpuUsage: freshGPU?.utilization,
                usage: cpuUsage,
                memoryUsed: Double(memory?.used ?? 0),
                swapUsed: Double(memory?.swapUsed ?? 0),
                batteryPercent: battery?.percent,
                totalWatts: snapshot.power?.total,
                batteryWatts: battery?.watts,
                netInPerSec: network?.totalInPerSec,
                netOutPerSec: network?.totalOutPerSec,
                diskReadPerSec: diskIO?.readPerSec,
                diskWritePerSec: diskIO?.writePerSec
            ))
            trimHistory()

            checkAlerts(averageTemp: average)

            let now = Date()
            if settings.loggingEnabled, now.timeIntervalSince(lastLoggedAt) >= Self.logInterval {
                lastLoggedAt = now
                HistoryDatabase.shared.append(HistoryDatabase.Entry(
                    averageTemp: average,
                    hottestTemp: hottest.celsius,
                    gpuTemp: gpuTemp,
                    fanRPM: fans.first?.rpm,
                    cpuUsage: cpuUsage,
                    memoryUsedGB: gigabytes(memory?.used ?? 0),
                    thermalState: thermalState.label,
                    batteryPercent: battery?.percent,
                    gpuUsage: freshGPU?.utilization,
                    gpuMemoryGB: freshGPU?.memoryUsed.map { gigabytes($0) },
                    netInBps: network?.totalInPerSec,
                    netOutBps: network?.totalOutPerSec,
                    diskReadBps: diskIO?.readPerSec,
                    diskWriteBps: diskIO?.writePerSec,
                    socWatts: snapshot.power?.total,
                    batteryWatts: battery?.watts
                ), at: now)
            }
        }
    }

    /// Diffs VM counters against the previous tick into per-second rates. A
    /// counter that went backwards (32-bit wrap or stat reset) reads as zero,
    /// not a spike.
    private func updateMemoryActivity(_ memory: MemorySnapshot?) {
        // Drop rates and baseline so a stale prior reading isn't diffed on return.
        guard let memory else {
            memoryActivity = nil
            previousMemorySnapshot = nil
            previousMemorySnapshotAt = nil
            return
        }
        let now = Date()
        defer { previousMemorySnapshot = memory; previousMemorySnapshotAt = now }
        guard let previous = previousMemorySnapshot,
              let previousAt = previousMemorySnapshotAt else { return }
        let elapsed = now.timeIntervalSince(previousAt)
        guard elapsed > 0 else { return }
        func rate(_ current: UInt64, _ before: UInt64) -> Double {
            guard current >= before else { return 0 }
            return Double(current - before) / elapsed
        }
        memoryActivity = MemoryActivity(
            pageInsPerSec: rate(memory.pageIns, previous.pageIns),
            pageOutsPerSec: rate(memory.pageOuts, previous.pageOuts),
            swapInsPerSec: rate(memory.swapIns, previous.swapIns),
            swapOutsPerSec: rate(memory.swapOuts, previous.swapOuts),
            compressionsPerSec: rate(memory.compressions, previous.compressions),
            decompressionsPerSec: rate(memory.decompressions, previous.decompressions)
        )
    }

    /// Publishes from the second sample onward: the first has no prior counters,
    /// so its 0 B/s rates are placeholders. A skipped read (nil) holds the last value.
    private func updateNetwork(_ snapshot: NetworkSnapshot?) {
        guard let snapshot else { return }
        if hasNetworkBaseline {
            network = snapshot
        } else {
            hasNetworkBaseline = true
        }
    }

    /// Same second-sample rule as `updateNetwork`.
    private func updateDiskIO(_ snapshot: DiskIOSnapshot?) {
        guard let snapshot else { return }
        if hasDiskIOBaseline {
            diskIO = snapshot
        } else {
            hasDiskIOBaseline = true
        }
    }

    /// Overheat: average CPU above the warning threshold for 2 minutes
    /// straight (10-minute cooldown between alerts). Thermal pressure:
    /// immediately, whenever macOS escalates to Serious or Critical.
    private func checkAlerts(averageTemp: Double) {
        if settings.notifyOverheat {
            if averageTemp >= settings.warnThreshold {
                if hotSince == nil { hotSince = Date() }
                if let since = hotSince,
                   Date().timeIntervalSince(since) >= Self.heatAlertAfter,
                   Date().timeIntervalSince(lastHeatAlert) >= Self.heatAlertCooldown {
                    alert(title: "Your Mac is running hot",
                          body: "Average CPU temperature has stayed above \(settings.format(settings.warnThreshold, decimals: 0)) for over 2 minutes. Currently \(settings.formatWithUnit(averageTemp)).",
                          id: "vitals.overheat")
                    lastHeatAlert = Date()
                }
            } else {
                hotSince = nil
            }
        }

        if settings.notifyThermal,
           thermalState == .serious || thermalState == .critical,
           thermalState.rawValue > previousThermalState.rawValue {
            alert(title: "Thermal pressure is \(thermalState.label)",
                  body: "macOS is throttling performance to cool down. Consider quitting heavy apps; the Overview lists the top processes.",
                  id: "vitals.thermal")
        }
        previousThermalState = thermalState
    }

    /// Notifies and records the alert in History's recent-alerts list.
    private func alert(title: String, body: String, id: String) {
        notifications.send(title: title, body: body, id: id)
        AlertLog.record(message: "\(title). \(body)", at: Date())
    }

    private static func average(of sensors: [Sensor], kind: Sensor.Kind) -> Double? {
        let values = sensors.filter { $0.kind == kind }.map(\.celsius)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Skips the write when unchanged, so views reading an often-stable value
    /// (`thermalState`, `hasLoaded`, …) don't re-render on every tick.
    private func assignIfChanged<T: Equatable>(_ target: inout T, to newValue: T) {
        guard target != newValue else { return }
        target = newValue
    }

    nonisolated static func classify(_ readings: [HIDSensors.Reading]) -> [Sensor] {
        var labelCounts: [String: Int] = [:]
        return readings.map { reading in
            let kind = kind(for: reading.name)
            var label = shortLabel(for: reading.name, kind: kind)
            // Disambiguate sensors that map to the same short label.
            let seen = labelCounts[label, default: 0]
            labelCounts[label] = seen + 1
            if seen > 0 { label += " (\(seen + 1))" }
            return Sensor(id: reading.name + "#\(seen)", label: label, kind: kind, celsius: reading.celsius)
        }
    }

    nonisolated private static func kind(for name: String) -> Sensor.Kind {
        let n = name.lowercased()
        if n.contains("pacc") || n.contains("eacc") || n.contains("tdie") || n.contains("cpu") { return .cpu }
        if n.contains("gpu") { return .gpu }
        if n.contains("nand") || n.contains("ssd") { return .storage }
        if n.contains("battery") || n.contains("gas gauge") { return .battery }
        return .other
    }

    nonisolated private static func shortLabel(for name: String, kind: Sensor.Kind) -> String {
        let number = name.reversed().prefix(while: \.isNumber).reversed().map(String.init).joined()
        let n = name.lowercased()
        switch kind {
        case .cpu:
            if n.contains("pacc") { return "P\(number)" }
            if n.contains("eacc") { return "E\(number)" }
            // M-series dies report as "PMU tdieN" / "PMU2 tdieN": two banks.
            if n.contains("tdie") { return n.contains("pmu2") ? "B\(number)" : "A\(number)" }
            return name
        case .gpu: return number.isEmpty ? "GPU" : "GPU \(number)"
        case .storage: return "SSD"
        case .battery: return "Battery"
        case .other: return name
        }
    }
}

extension ProcessInfo.ThermalState {
    var label: String {
        switch self {
        case .nominal: return "Nominal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }

    var tint: Color {
        switch self {
        case .nominal: return .green
        case .fair: return .yellow
        case .serious: return .orange
        case .critical: return .red
        @unknown default: return .gray
        }
    }
}

extension Array where Element == VitalsModel.Sample {
    /// Whether any sample carries a reading for `series`. Charts and metric
    /// tabs hide a series this Mac never reported.
    func hasReading(_ series: KeyPath<VitalsModel.Sample, Double?>) -> Bool {
        contains { $0[keyPath: series] != nil }
    }
}
