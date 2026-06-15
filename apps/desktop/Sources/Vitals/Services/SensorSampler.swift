import Foundation

/// Owns the sensor sources and takes every sample off the main thread.
/// One tick issues hundreds of syscalls — per-process rusage, the HID
/// sensor sweep, SMC fan reads — which would otherwise run on the UI
/// thread and cause hitches under load.
actor SensorSampler {
    struct Snapshot {
        let readings: [HIDSensors.Reading]
        let fans: [SMC.Fan]
        let hasSMC: Bool
        let cpuUsage: Double?
        let memory: MemorySnapshot?
        let topProcesses: [ProcessSampler.Process]
        let battery: BatterySnapshot?
        let gpu: GPUSnapshot?
        let power: PowerSnapshot?
    }

    private let hid = HIDSensors()
    private let smc = SMC()
    private let cpuSampler = CPUUsageSampler()
    private let processSampler = ProcessSampler()
    private let gpu = GPUSampler()
    private let power = SoCPowerSampler()

    // macOS's smoothed Maximum Capacity, refreshed rarely (it changes over
    // weeks) on a background task so the per-tick sample never waits on the
    // `system_profiler` spawn. Nil until the first read lands.
    private var batteryHealth: Double?
    private var batteryHealthCheckedAt = Date.distantPast
    private static let batteryHealthInterval: TimeInterval = 600

    func sample() -> Snapshot {
        let battery = Battery.read(officialHealth: batteryHealth)
        if battery != nil { refreshBatteryHealthIfStale() }
        return Snapshot(
            readings: hid.readAll(),
            fans: smc?.fans() ?? [],
            hasSMC: smc != nil,
            cpuUsage: cpuSampler.sample(),
            memory: MemoryStats.read(),
            topProcesses: processSampler.sample(top: 5),
            battery: battery,
            gpu: gpu.sample(),
            power: power.sample()
        )
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
