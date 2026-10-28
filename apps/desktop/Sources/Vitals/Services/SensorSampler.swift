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
        /// Whole-Mac draw in watts from the SMC, read alongside `power`.
        let systemWatts: Double?
        let diskHealth: DiskHealthSnapshot?
        let network: NetworkSnapshot?
        let diskIO: DiskIOSnapshot?
        let processTable: [ProcessSampler.Row]
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

    // Read every tick while something shows it, otherwise every 10 s (the
    // history cadence). The last reading stands in between.
    private var battery: BatterySnapshot?
    private var batteryReadAt = Date.distantPast
    private static let idleBatteryInterval: TimeInterval = 10

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
        var processTable = false
        /// A surface shows battery state; otherwise it refreshes every 10 s.
        var battery = false
        /// SSD and battery temperatures, shown but never logged.
        var peripheralTemps = false
    }

    /// The previous tick's needs. Power and process CPU are deltas against the
    /// last read, so the first read after a skipped stretch would average the
    /// whole gap. That read only resets the baseline and reports nothing.
    private var previousNeeds = Needs()

    func sample(_ needs: Needs) -> Snapshot {
        defer { previousNeeds = needs }
        // CoreWLAN and IOKit return autoreleased objects; drain them per sample
        // so they don't pile up on the actor's thread.
        return autoreleasepool {
            let battery = readBattery(live: needs.battery)
            refreshDiskHealthIfStale()
            let sweep = needs.topProcesses || needs.processTable
            var processes = sweep ? processSampler.sample(top: 5, includeTable: needs.processTable) : .empty
            if !(previousNeeds.topProcesses || previousNeeds.processTable) {
                processes = ProcessSampler.Sampled(byCPU: [], byMemory: [], table: processes.table)
            }
            var powerReading = needs.power ? power.sample() : nil
            if !previousNeeds.power { powerReading = nil }
            return Snapshot(
                sensors: VitalsModel.classify(hid.read(needs.peripheralTemps ? [.cpu, .gpu, .storage, .battery] : [.cpu, .gpu]))
                    .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending },
                fans: smc?.fans() ?? [],
                hasSMC: smc != nil,
                cpuUsage: cpuSampler.sample(),
                memory: MemoryStats.read(),
                topProcesses: processes.byCPU,
                topMemoryProcesses: processes.byMemory,
                battery: battery,
                gpu: needs.gpu ? gpu.sample() : nil,
                power: powerReading,
                systemWatts: needs.power ? smc?.read("PSTR").flatMap { $0 > 0 ? $0 : nil } : nil,
                diskHealth: diskHealth,
                // Byte counters are one sysctl, read every tick so the menu bar
                // and history get a continuous series.
                network: network.sample(includeDetails: needs.networkDetails),
                diskIO: disk.sample(),
                processTable: processes.table
            )
        }
    }

    private func readBattery(live: Bool) -> BatterySnapshot? {
        let now = Date()
        guard live || now.timeIntervalSince(batteryReadAt) >= Self.idleBatteryInterval else { return battery }
        batteryReadAt = now
        let packTemperature = smc?.read("TB0T").flatMap { (1..<100).contains($0) ? $0 : nil }
        battery = Battery.read(officialHealth: batteryHealth, fallbackTemperature: packTemperature)
        if battery != nil { refreshBatteryHealthIfStale() }
        return battery
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
