import Foundation

// The data model for one sampling tick — the Linux counterpart to the macOS
// SensorSampler.Snapshot. Every field is a real reading; anything the hardware
// doesn't expose is `nil` or empty, never a fabricated number.

/// A single temperature sensor reading, classified by what it measures so the
/// dashboard can group dies, GPU, storage, and battery the way the macOS app does.
public struct TempReading: Equatable, Sendable {
    public enum Kind: Sendable { case cpu, gpu, storage, battery, other }
    public let label: String
    public let celsius: Double
    public let kind: Kind

    public init(label: String, celsius: Double, kind: Kind) {
        self.label = label
        self.celsius = celsius
        self.kind = kind
    }
}

/// A fan's measured speed. `rpm == 0` is reported honestly as a stopped fan;
/// hardware that exposes no tachometer simply produces no `FanReading` at all.
public struct FanReading: Equatable, Sendable {
    public let label: String
    public let rpm: Int

    public init(label: String, rpm: Int) {
        self.label = label
        self.rpm = rpm
    }
}

/// Memory pressure, derived from the kernel's PSI signal (`/proc/pressure/memory`).
/// PSI is the closest real analogue to the macOS pressure level; the thresholds
/// are documented in `Meminfo.pressure(some:full:)`, not invented per reading.
public enum MemoryPressure: Sendable {
    case normal, warning, critical

    public var label: String {
        switch self {
        case .normal: return "Normal"
        case .warning: return "Warning"
        case .critical: return "Critical"
        }
    }
}

/// A memory picture from `/proc/meminfo`. Bytes throughout. `used` follows the
/// "total − available" convention `free`/`htop` use, so cached/buffers that the
/// kernel can reclaim don't read as used.
public struct MemorySnapshot: Equatable, Sendable {
    public let total: UInt64
    public let available: UInt64
    public let free: UInt64
    public let cached: UInt64
    public let swapTotal: UInt64
    public let swapUsed: UInt64

    public init(total: UInt64, available: UInt64, free: UInt64, cached: UInt64, swapTotal: UInt64, swapUsed: UInt64) {
        self.total = total
        self.available = available
        self.free = free
        self.cached = cached
        self.swapTotal = swapTotal
        self.swapUsed = swapUsed
    }

    public var used: UInt64 { total > available ? total - available : 0 }
    public var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
}

/// A battery reading from `/sys/class/power_supply`. Desktops without a battery
/// produce `nil` rather than a fake 100%.
public struct BatterySnapshot: Equatable, Sendable {
    public let percent: Double
    public let status: String
    public let isCharging: Bool
    public let onACPower: Bool
    /// Current full-charge capacity vs. design capacity ("Maximum Capacity").
    public let healthPercent: Double?
    public let cycleCount: Int?
    /// Signed power flow in watts: positive charging, negative on battery.
    public let watts: Double?

    public init(
        percent: Double,
        status: String,
        isCharging: Bool,
        onACPower: Bool,
        healthPercent: Double?,
        cycleCount: Int?,
        watts: Double?
    ) {
        self.percent = percent
        self.status = status
        self.isCharging = isCharging
        self.onACPower = onACPower
        self.healthPercent = healthPercent
        self.cycleCount = cycleCount
        self.watts = watts
    }
}

/// One process's CPU share. 100% means one core fully busy, matching `top` and
/// the macOS app — values above 100% are normal for multi-threaded work.
public struct ProcessUsage: Equatable, Sendable {
    public let pid: Int
    public let name: String
    public let cpuPercent: Double

    public init(pid: Int, name: String, cpuPercent: Double) {
        self.pid = pid
        self.name = name
        self.cpuPercent = cpuPercent
    }
}

/// Everything gathered in one tick. Mirrors the macOS `SensorSampler.Snapshot`.
public struct Snapshot: Sendable {
    public let temps: [TempReading]
    public let fans: [FanReading]
    public let cpuUsage: Double?
    public let memory: MemorySnapshot?
    public let pressure: MemoryPressure?
    public let topProcesses: [ProcessUsage]
    public let battery: BatterySnapshot?
    public let chipName: String?

    public init(
        temps: [TempReading] = [],
        fans: [FanReading] = [],
        cpuUsage: Double? = nil,
        memory: MemorySnapshot? = nil,
        pressure: MemoryPressure? = nil,
        topProcesses: [ProcessUsage] = [],
        battery: BatterySnapshot? = nil,
        chipName: String? = nil
    ) {
        self.temps = temps
        self.fans = fans
        self.cpuUsage = cpuUsage
        self.memory = memory
        self.pressure = pressure
        self.topProcesses = topProcesses
        self.battery = battery
        self.chipName = chipName
    }
}
