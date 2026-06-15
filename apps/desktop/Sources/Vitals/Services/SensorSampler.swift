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

    func sample() -> Snapshot {
        Snapshot(
            readings: hid.readAll(),
            fans: smc?.fans() ?? [],
            hasSMC: smc != nil,
            cpuUsage: cpuSampler.sample(),
            memory: MemoryStats.read(),
            topProcesses: processSampler.sample(top: 5),
            battery: Battery.read(),
            gpu: gpu.sample(),
            power: power.sample()
        )
    }
}
