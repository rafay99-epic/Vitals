import Foundation
import SwiftUI

/// The Overview's "is my Mac struggling?" read, composed from published readings:
/// thermal state, memory pressure, hottest CPU sensor, and fan speed. Pure, so
/// it can be unit-tested.
enum SystemHealth {
    /// Four bands mirroring `ProcessInfo.ThermalState`.
    enum Level: Int, Comparable {
        case good = 0, elevated, high, critical
        static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }

        var tint: Color {
            switch self {
            case .good: return .green
            case .elevated: return .yellow
            case .high: return .orange
            case .critical: return .red
            }
        }
    }

    static func thermalLevel(_ state: ProcessInfo.ThermalState) -> Level {
        switch state {
        case .nominal: return .good
        case .fair: return .elevated
        case .serious: return .high
        case .critical: return .critical
        @unknown default: return .good
        }
    }

    static func pressureLevel(_ pressure: MemoryPressure) -> Level {
        switch pressure {
        case .normal: return .good
        case .warning: return .elevated
        case .critical: return .critical
        }
    }

    /// Display bands for a CPU temperature in °C.
    static func temperatureLevel(celsius: Double) -> Level {
        switch celsius {
        case ..<75: return .good
        case ..<88: return .elevated
        case ..<96: return .high
        default: return .critical
        }
    }

    /// A fan near its rated ceiling signals load the machine is handling, so it
    /// never reads worse than "elevated".
    static func fanLevel(rpm: Double, maxRPM: Double) -> Level {
        guard maxRPM > 0 else { return .good }
        return rpm >= maxRPM * 0.95 ? .elevated : .good
    }

    /// macOS throttles at Serious and above. Used instead of clock speeds, which
    /// need root to read accurately.
    static func isThrottling(_ state: ProcessInfo.ThermalState) -> Bool {
        state == .serious || state == .critical
    }

    static func headline(level: Level, throttling: Bool) -> String {
        if throttling {
            return level == .critical ? "Throttling under heavy load" : "Throttling to cool down"
        }
        switch level {
        case .good: return "Running smoothly"
        case .elevated: return "Under load"
        case .high: return "Working hard"
        case .critical: return "Under pressure"
        }
    }
}
