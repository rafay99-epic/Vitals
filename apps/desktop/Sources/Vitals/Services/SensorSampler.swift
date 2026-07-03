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
        let cpuUsage: CPUUsage?
        let memory: MemorySnapshot?
        let topProcesses: [ProcessSampler.Process]
        let topMemoryProcesses: [ProcessSampler.Process]
        let battery: BatterySnapshot?
        let gpu: GPUSnapshot?
        let power: PowerSnapshot?
        let diskHealth: DiskHealthSnapshot?
        let network: NetworkSnapshot?
    }

    private let hid = HIDSensors()
    private let smc = SMC()
    private let cpuSampler = CPUUsageSampler()
    private let processSampler = ProcessSampler()
    private let gpu = GPUSampler()
    private let power = SoCPowerSampler()
    private let network = NetworkSampler()

    // macOS's smoothed Maximum Capacity, refreshed rarely (it changes over
    // weeks) on a background task so the per-tick sample never waits on the
    // `system_profiler` spawn. Nil until the first read lands.
    private var batteryHealth: Double?
    private var batteryHealthCheckedAt = Date.distantPast
    private static let batteryHealthInterval: TimeInterval = 600

    // SSD SMART changes over hours/days, so it's read at most every few minutes
    // off the sampling actor (the IOKit user-client round-trip shouldn't sit on
    // the tick), and the cached snapshot is served in between.
    private var diskHealth: DiskHealthSnapshot?
    private var diskHealthCheckedAt = Date.distantPast
    private static let diskHealthInterval: TimeInterval = 300

    /// `includeTopProcesses` gates the per-process rusage sweep — the heaviest
    /// part of a tick (a syscall per PID). It's only needed when the window is
    /// open or a process-CPU alert is armed; skipping it idle (menu-bar only)
    /// cuts the tick's cost noticeably.
    ///
    /// `includeGPU` / `includePower` gate the two IOReport samplers. They're
    /// only read when a surface the user can actually see needs them (the
    /// window's GPU/Power cards, a GPU widget, or a GPU-usage menu-bar metric or
    /// alert). When skipped, the snapshot carries nil and `VitalsModel` holds
    /// the last reading — so reopening the window shows the prior value until
    /// the next sample refreshes it, never a fabricated zero.
    func sample(includeTopProcesses: Bool, includeGPU: Bool = true, includePower: Bool = true) -> Snapshot {
        let battery = Battery.read(officialHealth: batteryHealth)
        if battery != nil { refreshBatteryHealthIfStale() }
        refreshDiskHealthIfStale()
        let processes = includeTopProcesses ? processSampler.sample(top: 5) : .empty
        return Snapshot(
            readings: hid.readAll(),
            fans: smc?.fans() ?? [],
            hasSMC: smc != nil,
            cpuUsage: cpuSampler.sample(),
            memory: MemoryStats.read(),
            topProcesses: processes.byCPU,
            topMemoryProcesses: processes.byMemory,
            battery: battery,
            gpu: includeGPU ? gpu.sample() : nil,
            power: includePower ? power.sample() : nil,
            diskHealth: diskHealth,
            // A few sysctls per tick — cheap enough to run ungated in v1.
            network: network.sample()
        )
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
