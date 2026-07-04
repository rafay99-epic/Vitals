import Foundation

/// A thing a custom alert can watch. Each metric maps to one live reading; a
/// reading that isn't available on this Mac (no GPU, a fanless model) simply
/// can't satisfy its rule, so such a rule never fires rather than firing on a
/// fabricated value.
enum AlertMetric: String, Codable, CaseIterable, Identifiable {
    case cpuTemp, cpuUsage, gpuUsage, memoryUsed, fanRPM, diskFree, battery, processCPU,
         networkDownload, networkUpload

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cpuTemp:    return "CPU temperature"
        case .cpuUsage:   return "CPU usage"
        case .gpuUsage:   return "GPU usage"
        case .memoryUsed: return "Memory used"
        case .fanRPM:     return "Fan speed"
        case .diskFree:   return "Free disk space"
        case .battery:    return "Battery"
        case .processCPU: return "A process's CPU"
        case .networkDownload: return "Network download"
        case .networkUpload:   return "Network upload"
        }
    }

    var symbol: String {
        switch self {
        case .cpuTemp:    return "thermometer.medium"
        case .cpuUsage:   return "cpu"
        case .gpuUsage:   return "cpu.fill"
        case .memoryUsed: return "memorychip"
        case .fanRPM:     return "fan"
        case .diskFree:   return "internaldrive"
        case .battery:    return "battery.50percent"
        case .processCPU: return "list.bullet"
        case .networkDownload: return "arrow.down.circle"
        case .networkUpload:   return "arrow.up.circle"
        }
    }

    /// Canonical unit the threshold is stored in. Temperature is always °C
    /// internally; the UI converts to the user's display unit.
    var unit: String {
        switch self {
        case .cpuTemp:    return "°C"
        case .fanRPM:     return "rpm"
        case .diskFree:   return "GB"
        case .networkDownload, .networkUpload: return "MB/s"
        default:          return "%"
        }
    }

    var isTemperature: Bool { self == .cpuTemp }

    /// Slider bounds + step in the canonical unit.
    var range: ClosedRange<Double> {
        switch self {
        case .cpuTemp:    return 40...110
        case .fanRPM:     return 0...6000
        case .diskFree:   return 1...200
        case .processCPU: return 10...400   // 100% = one core, so this can exceed 100
        case .networkDownload, .networkUpload: return 1...1000
        default:          return 0...100
        }
    }

    var step: Double {
        switch self {
        case .fanRPM:     return 50
        case .processCPU: return 10
        case .networkDownload, .networkUpload: return 5
        default:          return 1
        }
    }

    /// A sensible starting rule when this metric is chosen.
    var defaultComparison: AlertComparison {
        switch self {
        case .fanRPM, .diskFree, .battery: return .below  // low / stuck is the worry
        default:                           return .above  // high is the worry
        }
    }

    var defaultThreshold: Double {
        switch self {
        case .cpuTemp:    return 90
        case .fanRPM:     return 100   // effectively stopped
        case .diskFree:   return 10
        case .battery:    return 20
        case .processCPU: return 100
        case .networkDownload, .networkUpload: return 100   // MB/s — sustained heavy transfer
        default:          return 90
        }
    }
}

enum AlertComparison: String, Codable, CaseIterable, Identifiable {
    case above, below
    var id: String { rawValue }
    var label: String { self == .above ? "above" : "below" }

    func isSatisfied(value: Double, threshold: Double) -> Bool {
        self == .above ? value > threshold : value < threshold
    }
}

/// One user-defined alert: watch `metric`, fire when it stays `comparison`
/// `threshold` for `sustainedMinutes`. Codable so it persists; Equatable so the
/// settings list animates cleanly.
struct AlertRule: Identifiable, Codable, Equatable {
    var id = UUID()
    var metric: AlertMetric
    var comparison: AlertComparison
    var threshold: Double
    /// How long the condition must hold before firing. 0 = the moment it's true.
    var sustainedMinutes: Double
    var enabled: Bool

    init(metric: AlertMetric) {
        self.metric = metric
        self.comparison = metric.defaultComparison
        self.threshold = metric.defaultThreshold
        self.sustainedMinutes = 2
        self.enabled = true
    }

    func isSatisfied(by value: Double) -> Bool {
        comparison.isSatisfied(value: value, threshold: threshold)
    }
}

/// A snapshot of every value the alert engine can test, gathered once per tick.
/// Optionals are "not available on this Mac right now"; a rule on a nil reading
/// can't fire.
struct AlertReadings {
    var cpuTemp: Double?
    var cpuUsage: Double?
    var gpuUsage: Double?
    var memoryUsedPercent: Double?
    var minFanRPM: Double?
    var diskFreeGB: Double?
    var batteryPercent: Double?
    var topProcessCPU: Double?
    var topProcessName: String?
    var networkDownMBps: Double?
    var networkUpMBps: Double?

    func value(for metric: AlertMetric) -> Double? {
        switch metric {
        case .cpuTemp:    return cpuTemp
        case .cpuUsage:   return cpuUsage
        case .gpuUsage:   return gpuUsage
        case .memoryUsed: return memoryUsedPercent
        case .fanRPM:     return minFanRPM
        case .diskFree:   return diskFreeGB
        case .battery:    return batteryPercent
        case .processCPU: return topProcessCPU
        case .networkDownload: return networkDownMBps
        case .networkUpload:   return networkUpMBps
        }
    }
}
