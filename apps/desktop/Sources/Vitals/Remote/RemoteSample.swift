import Foundation

extension ProcessInfo.ThermalState {
    var wireName: String {
        switch self {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "nominal"
        }
    }

    var level: Int {
        switch self {
        case .nominal: return 0
        case .fair: return 1
        case .serious: return 2
        case .critical: return 3
        @unknown default: return 0
        }
    }
}

extension MemoryPressure {
    var wireName: String {
        switch self {
        case .normal: return "normal"
        case .warning: return "warning"
        case .critical: return "critical"
        }
    }

    var level: Int {
        switch self {
        case .normal: return 0
        case .warning: return 1
        case .critical: return 2
        }
    }
}

extension VitalsModel.Sensor.Kind {
    var wireName: String {
        switch self {
        case .cpu: return "cpu"
        case .gpu: return "gpu"
        case .storage: return "storage"
        case .battery: return "battery"
        case .other: return "other"
        }
    }
}

@MainActor
extension VitalsModel {
    func wireSample(seq: Int, topics: Set<String>, at date: Date) -> WireSample {
        var sample = WireSample(seq: seq, at: Int64(date.timeIntervalSince1970 * 1000))
        if topics.contains("cpu") {
            sample.cpu = WireCPU(
                overall: hasLoaded ? min(100, max(0, cpuUsage)) : nil,
                performance: cpuClusters.map { min(100, max(0, $0.performance)) },
                efficiency: cpuClusters.map { min(100, max(0, $0.efficiency)) },
                perCore: cpuPerCore.map { WireCore(id: $0.id, percent: min(100, max(0, $0.percent)), isPerformance: $0.isPerformance) }
            )
        }
        if topics.contains("gpu") {
            sample.gpu = WireGPU(
                utilization: gpu?.utilization.map { min(100, max(0, $0)) },
                memoryUsedBytes: gpu?.memoryUsed.map(Double.init),
                coreCount: gpu?.coreCount
            )
        }
        if topics.contains("thermal") {
            sample.thermal = WireThermal(
                state: thermalState.wireName,
                cpuC: averageCPUTemp,
                gpuC: gpuTemp,
                storageC: ssdTemp,
                batteryC: batteryTemp,
                sensors: cpuSensors.map { WireSensor(id: $0.id, label: $0.label, kind: $0.kind.wireName, celsius: $0.celsius) }
            )
        }
        if topics.contains("fans") {
            sample.fans = fans.map { WireFan(id: $0.id, rpm: $0.rpm, minRpm: $0.minRPM, maxRpm: $0.maxRPM) }
        }
        if topics.contains("memory"), let memory {
            sample.memory = WireMemory(
                totalBytes: Double(memory.total),
                usedBytes: Double(memory.used),
                appBytes: Double(memory.app),
                wiredBytes: Double(memory.wired),
                compressedBytes: Double(memory.compressed),
                cachedBytes: Double(memory.cached),
                freeBytes: Double(memory.free),
                swapUsedBytes: Double(memory.swapUsed),
                swapTotalBytes: Double(memory.swapTotal),
                pressure: memory.pressure.wireName
            )
        }
        if topics.contains("battery") {
            sample.battery = Nullable(wrappedValue: battery.map {
                WireBattery(
                    percent: min(100, max(0, $0.percent)),
                    charging: $0.isCharging,
                    externalPower: $0.externalPower,
                    watts: $0.watts,
                    timeRemainingMinutes: $0.timeRemainingMinutes.flatMap { $0 >= 0 ? $0 : nil },
                    cycleCount: $0.cycleCount.flatMap { $0 >= 0 ? $0 : nil },
                    healthPercent: $0.healthPercent,
                    temperatureC: $0.temperature,
                    condition: $0.condition
                )
            })
        }
        if topics.contains("power") {
            sample.power = Nullable(wrappedValue: power.map { WirePower(cpuWatts: $0.cpuWatts, gpuWatts: $0.gpuWatts, aneWatts: $0.aneWatts) })
        }
        if topics.contains("network"), let network {
            sample.network = WireNetwork(
                inBytesPerSec: network.totalInPerSec,
                outBytesPerSec: network.totalOutPerSec,
                wifiRssi: network.wifi?.rssi,
                primaryInterface: network.primaryInterfaceName
            )
        }
        if topics.contains("disk"), let diskIO {
            sample.disk = WireDisk(readBytesPerSec: diskIO.readPerSec, writeBytesPerSec: diskIO.writePerSec)
        }
        return sample
    }
}
