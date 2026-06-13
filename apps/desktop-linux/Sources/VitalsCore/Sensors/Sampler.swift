import Foundation

/// Gathers one `Snapshot` from every sensor source. Holds the stateful CPU and
/// process samplers (they need the previous tick to compute a delta). Phase 2
/// drives this off the main thread; here it's a plain synchronous reader.
public final class LinuxSensorSampler {
    private let cpu = CPUUsageSampler()
    private let processes = ProcessSampler()
    // The chip name never changes, so read it once.
    private lazy var chipName: String? = CPUInfo.read()

    public init() {}

    public func sample() -> Snapshot {
        let hwmon = Hwmon.read()
        // Thermal zones are a fallback only — they usually duplicate hwmon.
        let temps = hwmon.temps.isEmpty ? ThermalZones.read() : hwmon.temps
        let memory = Meminfo.read()

        return Snapshot(
            temps: temps,
            fans: hwmon.fans,
            cpuUsage: cpu.sample(),
            memory: memory.memory,
            pressure: memory.pressure,
            topProcesses: processes.sample(top: 5),
            battery: PowerSupply.read(),
            chipName: chipName
        )
    }
}
