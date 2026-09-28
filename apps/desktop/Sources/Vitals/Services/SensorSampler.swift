import Foundation

/// Owns the sensor sources and takes every sample off the main thread. One tick
/// issues hundreds of syscalls, which would hitch the UI on the main thread.
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
    // Network and disk diff counters between ticks, so each must be the same
    // instance every sample.
    private let network = NetworkStats()
    private let disk = DiskStats()

    // Changes over weeks and spawns `system_profiler`: refreshed twice a day.
    private var batteryHealth: Double?
    private var batteryHealthCheckedAt = Date.distantPast
    private static let batteryHealthInterval: TimeInterval = 12 * 3600

    // SMART changes over hours: refreshed every 5 minutes.
    private var diskHealth: DiskHealthSnapshot?
    private var diskHealthCheckedAt = Date.distantPast
    private static let diskHealthInterval: TimeInterval = 300

    /// Optional reads, each on only while a visible surface needs it. Skipped
    /// reads come back nil or empty; network details hold their last value.
    struct Needs {
        /// The per-process rusage sweep, the heaviest part of a tick.
        var topProcesses = false
        var gpu = false
        var power = false
        /// Wi-Fi link details and the default route.
        var networkDetails = false
    }

    func sample(_ needs: Needs) -> Snapshot {
        // CoreWLAN and IOKit return autoreleased objects; drain them per sample
        // so they don't pile up on the actor's thread.
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
                // Byte counters are one sysctl, read every tick so the menu bar
                // and history get a continuous series.
                network: network.sample(includeDetails: needs.networkDetails),
                diskIO: disk.sample()
            )
        }
    }

    /// Reads off the actor when stale. The time is stamped up front so a slow
    /// read can't start a second one; only a successful read replaces the cache.
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

    /// Same stamping and caching rules as `refreshDiskHealthIfStale`.
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
