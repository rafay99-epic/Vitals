import Foundation

/// Owns the sensor sources and takes every sample off the main thread.
/// One tick issues hundreds of syscalls — per-process rusage, the HID
/// sensor sweep, SMC fan reads — which would otherwise run on the UI
/// thread and cause hitches under load.
actor SensorSampler {
    struct Snapshot {
        /// Classified and sorted by label here, off the main thread.
        let sensors: [VitalsModel.Sensor]
        let fans: [SMC.Fan]
        let hasSMC: Bool
        let cpuUsage: CPUUsage?
        let memory: MemorySnapshot?
        let topProcesses: [ProcessSampler.Process]
        let topMemoryProcesses: [ProcessSampler.Process]
        let battery: BatterySnapshot?
        let gpu: GPUSnapshot?
        let power: PowerSnapshot?
        let diskHealth: DiskHealthSnapshot?
        let network: NetworkSnapshot?
        let diskIO: DiskIOSnapshot?
    }

    private let hid = HIDSensors()
    private let smc = SMC()
    private let cpuSampler = CPUUsageSampler()
    private let processSampler = ProcessSampler()
    private let gpu = GPUSampler()
    private let power = SoCPowerSampler()
    // Stateful: holds the previous tick's byte counters to diff into rates, so
    // it must be the same instance every sample.
    private let network = NetworkStats()
    // Same statefulness rule: per-driver disk counters diff into rates.
    private let disk = DiskStats()

    // macOS's smoothed Maximum Capacity changes over weeks, and reading it
    // spawns `system_profiler`, so it's refreshed twice a day off the tick.
    private var batteryHealth: Double?
    private var batteryHealthCheckedAt = Date.distantPast
    private static let batteryHealthInterval: TimeInterval = 12 * 3600

    // SSD SMART changes over hours/days: read every few minutes off the tick,
    // cached in between.
    private var diskHealth: DiskHealthSnapshot?
    private var diskHealthCheckedAt = Date.distantPast
    private static let diskHealthInterval: TimeInterval = 300

    /// Which optional reads to take. Each is only on while a surface the user
    /// can see needs it; skipped reads come back nil (or hold their last value,
    /// for network details) and `VitalsModel` keeps the last reading on screen,
    /// never a fabricated zero.
    struct Needs {
        /// The per-process rusage sweep, the heaviest part of a tick.
        var topProcesses = false
        var gpu = false
        var power = false
        /// Wi-Fi link details and the default route.
        var networkDetails = false
    }

    func sample(_ needs: Needs) -> Snapshot {
        // CoreWLAN and IOKit hand back autoreleased objects; drain them per
        // sample instead of letting them pile up on the actor's thread.
        autoreleasepool {
            let battery = Battery.read(officialHealth: batteryHealth)
            if battery != nil { refreshBatteryHealthIfStale() }
            refreshDiskHealthIfStale()
            let processes = needs.topProcesses ? processSampler.sample(top: 5) : .empty
            return Snapshot(
                sensors: VitalsModel.classify(hid.readAll())
                    .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending },
                fans: smc?.fans() ?? [],
                hasSMC: smc != nil,
                cpuUsage: cpuSampler.sample(),
                memory: MemoryStats.read(),
                topProcesses: processes.byCPU,
                topMemoryProcesses: processes.byMemory,
                battery: battery,
                gpu: needs.gpu ? gpu.sample() : nil,
                power: needs.power ? power.sample() : nil,
                diskHealth: diskHealth,
                // Byte counters are one sysctl; the menu bar and history want a
                // continuous series, so they're read every tick.
                network: network.sample(includeDetails: needs.networkDetails),
                diskIO: disk.sample()
            )
        }
    }

    /// Refreshes the cached SSD SMART snapshot off the sampling actor if it's
    /// stale, serving the last good value in between. Stamps the time up front so
    /// a slow user-client call can't spawn a second read; only a successful read
    /// replaces the cache (mirrors `refreshBatteryHealthIfStale`).
    private func refreshDiskHealthIfStale() {
        guard Date().timeIntervalSince(diskHealthCheckedAt) >= Self.diskHealthInterval else { return }
        diskHealthCheckedAt = Date()
        Task.detached { [weak self] in
            let value = DiskHealth.read()
            await self?.storeDiskHealth(value)
        }
    }

    private func storeDiskHealth(_ value: DiskHealthSnapshot?) {
        if let value { diskHealth = value }
    }

    /// Kicks off a background read of macOS's Maximum Capacity if the cached
    /// value is stale. Stamps the time up front so a slow read can't spawn a
    /// second `system_profiler`; only a successful read updates the cache.
    private func refreshBatteryHealthIfStale() {
        guard Date().timeIntervalSince(batteryHealthCheckedAt) >= Self.batteryHealthInterval else { return }
        batteryHealthCheckedAt = Date()
        Task.detached { [weak self] in
            let value = BatteryHealth.maximumCapacityPercent()
            await self?.storeBatteryHealth(value)
        }
    }

    private func storeBatteryHealth(_ value: Double?) {
        if let value { batteryHealth = value }
    }
}
