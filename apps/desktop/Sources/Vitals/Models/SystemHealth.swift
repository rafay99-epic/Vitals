import Foundation
import SwiftUI

/// An honest "is my Mac struggling right now?" read, composed only from numbers
/// the model already publishes: macOS's own thermal state (which *is* its
/// throttling signal), memory pressure, the hottest CPU sensor and fan speed.
/// It invents nothing — every factor the Health tab shows points back at a real
/// reading, and the colour bands here only tint a value that's displayed beside
/// them. The classification is pure so it can be unit-tested.
enum SystemHealth {
    /// Four bands mirroring `ProcessInfo.ThermalState`, so thermal pressure maps
    /// across without loss.
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

    /// Display bands for a CPU package temperature in °C. The figure itself is
    /// always shown next to the colour, so this only decides hue — it never
    /// stands in for the number.
    static func temperatureLevel(celsius: Double) -> Level {
        switch celsius {
        case ..<75: return .good
        case ..<88: return .elevated
        case ..<96: return .high
        default: return .critical
        }
    }

    /// A fan pinned near its rated ceiling means cooling is working hard — a sign
    /// of load, but the machine is handling it, so it never reads worse than
    /// "elevated".
    static func fanLevel(rpm: Double, maxRPM: Double) -> Level {
        guard maxRPM > 0 else { return .good }
        return rpm >= maxRPM * 0.95 ? .elevated : .good
    }

    /// macOS throttles to protect the machine at Serious and above; that state
    /// *is* the throttle signal, so it's reported as one rather than guessed at
    /// from clock speeds (which need root to read accurately).
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
