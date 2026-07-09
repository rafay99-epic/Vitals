import Foundation
import SwiftUI
import Combine
import AppKit

@MainActor
final class VitalsModel: ObservableObject {
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
        let netInPerSec: Double?     // network download, bytes/s — nil until the 2nd sample
        let netOutPerSec: Double?    // network upload, bytes/s — nil until the 2nd sample
    }

    @Published private(set) var cpuSensors: [Sensor] = []
    @Published private(set) var gpuTemp: Double?
    /// GPU utilization and memory (nil when there's no readable GPU, e.g. a VM).
    @Published private(set) var gpu: GPUSnapshot?
    @Published private(set) var ssdTemp: Double?
    @Published private(set) var batteryTemp: Double?
    @Published private(set) var fans: [SMC.Fan] = []
    @Published private(set) var hasSMC = false
    @Published private(set) var history: [Sample] = []
    /// `history` thinned for drawing — charts can't show more points than
    /// pixels, and Swift Charts rebuild cost scales with mark count.
    @Published private(set) var chartHistory: [Sample] = []
    @Published private(set) var cpuUsage: Double = 0
    /// Per-cluster CPU utilisation (Apple Silicon). Nil when there's no trusted
    /// P/E split — `cpuUsage` (the blended figure) still applies.
    @Published private(set) var cpuClusters: (performance: Double, efficiency: Double)?
    /// Per-core utilisation for the CPU tab's deep view. Empty without a trusted split.
    @Published private(set) var cpuPerCore: [CoreUsage] = []
    @Published private(set) var memory: MemorySnapshot?
    /// Live VM page-traffic rates (page-ins/outs, swap-ins/outs, compress/
    /// decompress). Nil until the second sample — a rate needs a prior reading.
    @Published private(set) var memoryActivity: MemoryActivity?
    @Published private(set) var thermalState = ProcessInfo.processInfo.thermalState
    @Published private(set) var topProcesses: [ProcessSampler.Process] = []
    /// The heaviest memory consumers, top-first. Sampled in the same sweep as
    /// `topProcesses` (which is CPU-ordered), so it costs no extra syscalls.
    @Published private(set) var topMemoryProcesses: [ProcessSampler.Process] = []
    /// The previous tick's cumulative VM counters + when they were read, kept to
    /// diff into `memoryActivity`.
    private var previousMemorySnapshot: MemorySnapshot?
    private var previousMemorySnapshotAt: Date?
    @Published private(set) var battery: BatterySnapshot?
    /// The internal SSD's SMART health (wear, endurance, power-on hours…). Nil
    /// on a Mac/VM that doesn't expose SMART, or for the first tick or two.
    @Published private(set) var diskHealth: DiskHealthSnapshot?
    /// Live SoC power draw (CPU/GPU/ANE rails). Nil until the second sample —
    /// power is an energy delta and needs a prior reading — and on the rare
    /// machine where IOReport is unavailable.
    @Published private(set) var power: PowerSnapshot?
    /// Live per-interface network throughput (Wi-Fi/Ethernet) plus Wi-Fi link
    /// details. Nil until the second sample — the first reading has no prior
    /// byte counters, so its 0 B/s rates would be placeholders, not
    /// measurements (same rule as `memoryActivity`/`power`).
    @Published private(set) var network: NetworkSnapshot?
    /// True once the first network reading landed; publication starts with the
    /// second (see `network`).
    private var hasNetworkBaseline = false
    /// False until the first sample lands — drives the dashboard loading state.
    @Published private(set) var hasLoaded = false
    /// True when a sample overran the watchdog (a sensor syscall wedged). The
    /// last readings stay on screen, but this lets the UI flag that they're not
    /// updating rather than silently presenting stale numbers as live.
    @Published private(set) var sensorsStalled = false

    let memoryTotal = ProcessInfo.processInfo.physicalMemory

    /// True only when a sample arrived but carried no usable readings at all
    /// (no temps, no fans, no memory) — e.g. a VM or restricted hardware.
    /// On real Macs memory always reads, so this stays false.
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
    private let alertEngine = AlertEngine()
    private var timer: Timer?
    private var isSampling = false
    /// Whether the main window is open. Top-process sampling (the costliest part
    /// of a tick) is skipped when it's closed and no process-CPU alert needs it.
    private var mainWindowVisible = false
    /// True while the Mac is asleep — set by `NSWorkspace.willSleep/didWake`
    /// observers. The timer is torn down on sleep and rebuilt on wake, so no
    /// sensor reads happen (and no battery is burned) while the machine is
    /// suspended. The flag also guards `start()` so a settings change made while
    /// asleep can't restart sampling until wake.
    private var isAsleep = false
    /// Whether a desktop widget showing GPU data (the GPU or Combined widget) is
    /// on screen. The widget reads `self.gpu`, so the IOReport GPU sample is only
    /// skipped when this is false too — never let a visible widget go stale.
    private var gpuWidgetVisible = false
    /// `NSWorkspace` sleep/wake observers; removed in `deinit`.
    private var sleepObservers: [NSObjectProtocol] = []

    /// Call when the main window opens/closes (ContentView appear/disappear).
    func setMainWindowVisible(_ visible: Bool) { mainWindowVisible = visible }

    /// Call when a GPU-bearing widget (`.gpu` / `.combined`) appears/disappears
    /// so the sampler keeps the IOReport GPU reading live while it's on screen.
    func setGPUWidgetVisible(_ visible: Bool) { gpuWidgetVisible = visible }

    /// Test/diagnostic exposure of whether the sampling timer is armed. Sleep
    /// tears it down; wake rebuilds it.
    internal var isSamplingTimerActive: Bool { timer != nil }

    private var needsTopProcesses: Bool {
        mainWindowVisible || settings.alertRules.contains { $0.enabled && $0.metric == .processCPU }
    }
    /// Whether the IOReport GPU sample is needed this tick. The GPU reading is
    /// only consumed by surfaces the user can see: the window's GPU card, a GPU
    /// or Combined desktop widget, a GPU-usage menu-bar metric, or a GPU-usage
    /// alert. Menu-bar-only with no GPU metric → skip the read and hold the last
    /// value, cutting an IOReport round-trip every tick.
    private var needsGPU: Bool {
        mainWindowVisible
            || gpuWidgetVisible
            || (settings.showMenuBar && settings.menuBarMetrics.contains(.gpuUsage))
            || settings.alertRules.contains { $0.enabled && $0.metric == .gpuUsage }
    }
    /// Whether the IOReport SoC-power sample is needed. Power draw only appears
    /// in the window's Power card — no widget, menu-bar metric, or alert reads
    /// it — so it's skipped entirely when the window is closed.
    private var needsPower: Bool { mainWindowVisible }
    private var cancellables: Set<AnyCancellable> = []
    private static let maxChartPoints = 300
    /// A single sample must finish within this long or the watchdog frees the
    /// pipeline. Generous — a real sample is milliseconds; this only fires when
    /// a syscall has genuinely wedged.
    private static let sampleTimeout: TimeInterval = 5

    // Overheat alerting state.
    private var hotSince: Date?
    private var lastHeatAlert: Date = .distantPast
    private var previousThermalState = ProcessInfo.processInfo.thermalState
    private static let heatAlertAfter: TimeInterval = 120
    private static let heatAlertCooldown: TimeInterval = 600

    // Custom-rule alerting: free disk space is read on a throttle since it
    // barely moves and statfs needn't run every tick.
    private var diskFreeGB: Double?
    private var diskCheckedAt: Date = .distantPast
    private static let diskCheckInterval: TimeInterval = 30

    init(settings: AppSettings) {
        self.settings = settings
        settings.$refreshInterval
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in self?.restartTimerIfAwake() }
            .store(in: &cancellables)
        // Power state and the battery-throttle toggle both change the effective
        // cadence, so a transition restarts the timer at the new interval. The
        // model refreshes the power state each tick (`updatePowerState`), and
        // these sinks only fire on an actual transition (AppSettings reassigns
        // `isOnBattery`/`isLowPowerMode` only when they move).
        settings.$isOnBattery
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in self?.restartTimerIfAwake() }
            .store(in: &cancellables)
        settings.$isLowPowerMode
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in self?.restartTimerIfAwake() }
            .store(in: &cancellables)
        settings.$reduceOnBattery
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in self?.restartTimerIfAwake() }
            .store(in: &cancellables)
        settings.$historyMinutes
            .dropFirst()
            .sink { [weak self] _ in self?.trimHistory() }
            .store(in: &cancellables)
        // Ask for notification permission as soon as any alert is enabled.
        settings.$notifyOverheat
            .merge(with: settings.$notifyThermal)
            .filter { $0 }
            .sink { [weak self] _ in self?.notifications.requestAuthorizationIfNeeded() }
            .store(in: &cancellables)
        settings.$alertRules
            .filter { $0.contains(where: \.enabled) }
            .sink { [weak self] _ in self?.notifications.requestAuthorizationIfNeeded() }
            .store(in: &cancellables)

        // Pause sampling on system sleep and resume on wake — no sensor reads,
        // no wakeups, no battery drain while the Mac is suspended. Registered
        // last: the closures capture self, which must be fully initialized.
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
        sleepObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
    }

    /// Never below 0.5 s — the Picker only offers 1/2/5, but a corrupted
    /// UserDefaults value of 0 would otherwise divide-by-zero here and below.
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

    /// Restarts the timer only while awake **and already running** — a cadence-
    /// relevant setting change made while asleep must not resume sampling until
    /// the Mac wakes, and the `timer != nil` guard blocks a re-entrant call
    /// during the first `start()` (where `tick()` runs before `self.timer` is
    /// assigned) from scheduling a second, leaked timer.
    private func restartTimerIfAwake() {
        guard !isAsleep, timer != nil else { return }
        restartTimer()
    }

    /// Tears down the sampling timer on system sleep. An in-flight tick (if any)
    /// is allowed to finish — it's one harmless extra sample — but no new ticks
    /// fire until `handleWake`.
    private func handleSleep() {
        guard !isAsleep else { return }
        isAsleep = true
        timer?.invalidate()
        timer = nil
        Log.notice(.sampler, "system sleeping — sampling paused")
    }

    /// Rebuilds the sampling timer on wake and immediately takes a fresh sample
    /// so readings recover from the gap at once. The cadence is re-read from
    /// `effectiveRefreshInterval`, so a power-source change that happened during
    /// sleep (unplugged in clamshell, woken on battery) takes effect immediately.
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
        chartHistory = Self.downsample(history, to: Self.maxChartPoints)
    }

    /// Kicks off one sample on the sampler's executor and publishes the
    /// result back here. `isSampling` drops a tick rather than letting a
    /// slow sample (heavily loaded machine) queue up behind itself.
    ///
    /// A watchdog backs this up: a sensor syscall can wedge (a stuck IOKit
    /// driver, a degraded VM). Without it, `isSampling` would stay true forever
    /// and the app would freeze on stale numbers with no recovery — the worst
    /// outcome for a monitor. If the sample overruns `sampleTimeout`, the
    /// pipeline is freed so the next tick retries, and `sensorsStalled` lets
    /// the UI stop pretending the frozen readings are live.
    private func tick() {
        guard !isSampling, !isAsleep else { return }
        isSampling = true
        // Keep the cadence in sync with the power source first. This may publish
        // `isOnBattery`/`isLowPowerMode` and re-enter `restartTimerIfAwake` →
        // `start` → `tick`; the `!isSampling` guard above makes that re-entrant
        // tick a no-op, so only this sample actually runs.
        settings.updatePowerState()

        let includeTopProcesses = needsTopProcesses
        let includeGPU = needsGPU
        let includePower = needsPower
        let work = Task { [weak self] in
            guard let self else { return }
            let snapshot = await self.sampler.sample(includeTopProcesses: includeTopProcesses,
                                                     includeGPU: includeGPU,
                                                     includePower: includePower)
            guard !Task.isCancelled else { return }
            self.apply(snapshot, sampledGPU: includeGPU)
            self.assignIfChanged(&self.sensorsStalled, to: false)
            self.isSampling = false
        }

        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.sampleTimeout * 1_000_000_000))
            guard let self, self.isSampling else { return }  // already finished → nothing to do
            work.cancel()
            // Log only on the transition into a stall, not every stalled tick.
            if !self.sensorsStalled {
                Log.notice(.sampler, "a sensor sample exceeded \(Self.sampleTimeout)s and was cancelled — readings may pause")
            }
            self.assignIfChanged(&self.sensorsStalled, to: true)
            self.isSampling = false
        }
    }

    private func apply(_ snapshot: SensorSampler.Snapshot, sampledGPU: Bool) {
        let classified = Self.classify(snapshot.readings)

        cpuSensors = classified.filter { $0.kind == .cpu }
            .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
        // Gate the cheap, often-stable scalars: `@Published` fires
        // `objectWillChange` on every assignment regardless of whether the value
        // actually moved, so reassigning `thermalState` to the same enum each
        // tick would still invalidate every observing view. Only reassign when
        // the value genuinely changes — the temperature Double?s drift most
        // ticks but the compare is trivial, and `thermalState`/`hasSMC`/
        // `hasLoaded`/`sensorsStalled` barely move, so their observers (Health
        // tab, Fan card, the loading state) skip re-rendering on a normal tick.
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
        // Only reassign GPU when it was actually sampled this tick. When the
        // window/widgets/metric don't need it, the sampler returns nil and we
        // hold the last reading — so reopening the window shows the prior value
        // until the next tick refreshes it, never a fabricated blank.
        if sampledGPU { gpu = snapshot.gpu }
        // Power is nil both when skipped and when IOReport had no delta this
        // tick; `if let` holds the last good reading in either case. The history
        // Sample uses the fresh `snapshot.power?.total`, so a skip is an honest
        // gap in the chart, not a flat-held value.
        if let power = snapshot.power { self.power = power }
        assignIfChanged(&hasLoaded, to: true)

        // Custom rules run every tick — disk/battery/process alerts shouldn't
        // depend on temperature sensors being present.
        evaluateAlertRules()

        if let average = averageCPUTemp, let hottest = hottestCPUSensor {
            history.append(Sample(
                id: Date(),
                time: Date(),
                averageCPU: average,
                hottestCPU: hottest.celsius,
                gpu: gpuTemp,
                gpuUsage: gpu?.utilization,
                usage: cpuUsage,
                memoryUsed: Double(memory?.used ?? 0),
                swapUsed: Double(memory?.swapUsed ?? 0),
                batteryPercent: battery?.percent,
                // The fresh tick's reading (not the sticky `self.power`), so a
                // missed IOReport sample is an honest gap, not a flat-held value.
                totalWatts: snapshot.power?.total,
                // The published reading (nil until the 2nd sample), so the
                // first tick is an honest gap, never a fabricated 0 B/s.
                netInPerSec: network?.totalInPerSec,
                netOutPerSec: network?.totalOutPerSec
            ))
            trimHistory()

            checkAlerts(averageTemp: average)

            if settings.loggingEnabled {
                HistoryDatabase.shared.append(HistoryDatabase.Entry(
                    averageTemp: average,
                    hottestTemp: hottest.celsius,
                    gpuTemp: gpuTemp,
                    fanRPM: fans.first?.rpm,
                    cpuUsage: cpuUsage,
                    memoryUsedGB: gigabytes(memory?.used ?? 0),
                    thermalState: thermalState.label,
                    batteryPercent: battery?.percent,
                    gpuUsage: gpu?.utilization,
                    gpuMemoryGB: gpu?.memoryUsed.map { gigabytes($0) },
                    netInBps: network?.totalInPerSec,
                    netOutBps: network?.totalOutPerSec
                ))
            }
        }
    }

    /// Turn the snapshot's running VM counters into per-second rates by diffing
    /// against the previous tick. Publishes nil until a second sample lands (a
    /// rate needs two readings), and treats a counter that went backwards — a
    /// 32-bit wrap or a stat reset — as zero rather than a fabricated spike.
    private func updateMemoryActivity(_ memory: MemorySnapshot?) {
        // Memory unavailable (a VM/restricted Mac): drop the published rates and
        // the baseline so the UI stops presenting the last sample's rates as live
        // and doesn't compute a bogus rate against a stale prior reading on return.
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

    /// Publishes the network reading from the second sample onward. The first
    /// reading has no prior counters, so its 0 B/s rates are placeholders, not
    /// measurements — a rate needs two readings. A skipped read (nil) holds the
    /// last published snapshot rather than blanking live surfaces, like `gpu`.
    private func updateNetwork(_ snapshot: NetworkSnapshot?) {
        guard let snapshot else { return }
        if hasNetworkBaseline {
            network = snapshot
        } else {
            hasNetworkBaseline = true
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
                    notifications.send(
                        title: "Your Mac is running hot",
                        body: "Average CPU temperature has stayed above \(settings.format(settings.warnThreshold, decimals: 0)) for over 2 minutes — currently \(settings.formatWithUnit(averageTemp)).",
                        id: "vitals.overheat"
                    )
                    lastHeatAlert = Date()
                }
            } else {
                hotSince = nil
            }
        }

        if settings.notifyThermal,
           thermalState == .serious || thermalState == .critical,
           thermalState.rawValue > previousThermalState.rawValue {
            notifications.send(
                title: "Thermal pressure is \(thermalState.label)",
                body: "macOS is throttling performance to cool down. Consider quitting heavy apps — check Top Processes in Vitals.",
                id: "vitals.thermal"
            )
        }
        previousThermalState = thermalState
    }

    // MARK: Custom alert rules

    /// Runs the user's rules against the current readings and sends a
    /// notification for each that fires. The engine handles the sustain/cooldown
    /// timing; we just format the message in the user's units.
    private func evaluateAlertRules() {
        // Zero work in the common case: no rules, or none enabled.
        guard settings.alertRules.contains(where: \.enabled) else { return }
        let readings = currentAlertReadings()
        for (rule, value) in alertEngine.evaluate(rules: settings.alertRules, readings: readings, now: Date()) {
            let body = alertMessage(rule: rule, value: value, readings: readings)
            notifications.send(title: "Vitals alert", body: body, id: "vitals.rule.\(rule.id.uuidString)")
            AlertLog.record(message: body, at: Date())
        }
    }

    private func currentAlertReadings() -> AlertReadings {
        refreshDiskFreeIfStale()
        let topProcess = topProcesses.max { $0.cpuPercent < $1.cpuPercent }
        return AlertReadings(
            cpuTemp: hottestCPUSensor?.celsius,
            cpuUsage: cpuUsage,
            gpuUsage: gpu?.utilization,
            memoryUsedPercent: memory.map { $0.total > 0 ? Double($0.used) / Double($0.total) * 100 : 0 },
            minFanRPM: fans.isEmpty ? nil : fans.map(\.rpm).min(),
            diskFreeGB: diskFreeGB,
            batteryPercent: battery?.percent,
            topProcessCPU: topProcess?.cpuPercent,
            topProcessName: topProcess?.name,
            // Canonical MB/s to match the rule's stored threshold unit. Nil
            // until the second sample — a rule can't fire on a placeholder.
            networkDownMBps: network.map { $0.totalInPerSec / 1_000_000 },
            networkUpMBps: network.map { $0.totalOutPerSec / 1_000_000 }
        )
    }

    private func refreshDiskFreeIfStale() {
        guard Date().timeIntervalSince(diskCheckedAt) >= Self.diskCheckInterval else { return }
        diskCheckedAt = Date()
        if let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let bytes = values.volumeAvailableCapacityForImportantUsage {
            diskFreeGB = Double(bytes) / 1_073_741_824
        }
    }

    /// A short, human notification body in the user's units. Process rules name
    /// the offending app.
    private func alertMessage(rule: AlertRule, value: Double, readings: AlertReadings) -> String {
        let now = formattedAlertValue(rule.metric, value)
        let limit = formattedAlertValue(rule.metric, rule.threshold)
        if rule.metric == .processCPU {
            return "\(readings.topProcessName ?? "A process") is using \(now) CPU — \(rule.comparison.label) your \(limit) alert."
        }
        return "\(rule.metric.label) is \(now) — \(rule.comparison.label) your \(limit) alert."
    }

    private func formattedAlertValue(_ metric: AlertMetric, _ value: Double) -> String {
        if metric.isTemperature { return settings.formatWithUnit(value, decimals: 0) }
        switch metric {
        case .fanRPM:   return "\(Int(value)) rpm"
        case .diskFree: return String(format: "%.0f GB", value)
        // The reading is canonical MB/s; NetworkFormat speaks bytes/s.
        case .networkDownload, .networkUpload: return NetworkFormat.rate(value * 1_000_000)
        default:        return "\(Int(value))%"
        }
    }

    /// Evenly thins `samples` to at most `maxCount` points, always keeping
    /// the first and the newest. Indices step by more than one whenever
    /// thinning happens, so no sample (or id) repeats.
    static func downsample(_ samples: [Sample], to maxCount: Int) -> [Sample] {
        guard samples.count > maxCount, maxCount > 1 else { return samples }
        let stride = Double(samples.count - 1) / Double(maxCount - 1)
        return (0..<maxCount).map { samples[Int((Double($0) * stride).rounded())] }
    }

    private static func average(of sensors: [Sensor], kind: Sensor.Kind) -> Double? {
        let values = sensors.filter { $0.kind == kind }.map(\.celsius)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Reassign `target` only when `newValue` differs — `@Published` fires
    /// `objectWillChange` on every assignment regardless of whether the value
    /// moved, so this gates the cheap, often-stable Equatable properties
    /// (`thermalState`, `hasSMC`, `hasLoaded`, `sensorsStalled`, the temperature
    /// Double?s) so their observers skip re-rendering on a tick where nothing
    /// actually changed. Generic over `Equatable` so it costs nothing for the
    /// array/struct properties, which stay ungated.
    private func assignIfChanged<T: Equatable>(_ target: inout T, to newValue: T) {
        guard target != newValue else { return }
        target = newValue
    }

    static func classify(_ readings: [HIDSensors.Reading]) -> [Sensor] {
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

    private static func kind(for name: String) -> Sensor.Kind {
        let n = name.lowercased()
        if n.contains("pacc") || n.contains("eacc") || n.contains("tdie") || n.contains("cpu") { return .cpu }
        if n.contains("gpu") { return .gpu }
        if n.contains("nand") || n.contains("ssd") { return .storage }
        if n.contains("battery") || n.contains("gas gauge") { return .battery }
        return .other
    }

    private static func shortLabel(for name: String, kind: Sensor.Kind) -> String {
        let number = name.reversed().prefix(while: \.isNumber).reversed().map(String.init).joined()
        let n = name.lowercased()
        switch kind {
        case .cpu:
            if n.contains("pacc") { return "P\(number)" }
            if n.contains("eacc") { return "E\(number)" }
            // M-series dies report as "PMU tdieN" / "PMU2 tdieN" — two banks.
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
