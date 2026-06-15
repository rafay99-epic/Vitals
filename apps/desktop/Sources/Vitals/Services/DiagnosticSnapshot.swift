import Foundation
import AppKit

/// Builds a plain-text snapshot of every current reading and copies it to the
/// clipboard — handy to paste into a support thread or a note. Read-only and
/// honest: a missing subsystem is omitted, never fabricated.
@MainActor
enum DiagnosticSnapshot {
    static func copyToPasteboard(model: VitalsModel, settings: AppSettings) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text(model: model, settings: settings), forType: .string)
    }

    static func text(model: VitalsModel, settings: AppSettings) -> String {
        var lines: [String] = []
        lines.append("Vitals diagnostic snapshot")
        lines.append("\(HardwareInfo.chipName) · \(HardwareInfo.osVersion) · up \(HardwareInfo.uptimeText)")
        lines.append("Captured \(Date().formatted(date: .abbreviated, time: .standard))")
        lines.append("")

        if let average = model.averageCPUTemp, let hottest = model.hottestCPUSensor {
            lines.append("CPU temp:   avg \(settings.formatWithUnit(average)), hottest \(settings.formatWithUnit(hottest.celsius)) (\(hottest.label))")
        }
        lines.append("CPU load:   \(Int(model.cpuUsage.rounded()))% across \(HardwareInfo.coreCount) cores")
        lines.append("Thermal:    \(model.thermalState.label) (reported by macOS)")

        if let gpu = model.gpu {
            var line = "GPU:        "
            line += gpu.utilization.map { "\(Int($0.rounded()))% util" } ?? "util —"
            if let used = gpu.memoryUsed { line += String(format: ", %.2f GB in use", gigabytes(used)) }
            if let cores = gpu.coreCount { line += " (\(cores)-core)" }
            lines.append(line)
        }

        if let memory = model.memory {
            lines.append(String(format: "Memory:     %.2f / %.0f GB used, %@ pressure, %.2f GB swap",
                                gigabytes(memory.used), gigabytes(memory.total),
                                memory.pressure.label, gigabytes(memory.swapUsed)))
        }

        if let power = model.power {
            lines.append(String(format: "SoC power:  CPU %.2f W, GPU %.2f W, ANE %.2f W",
                                power.cpuWatts, power.gpuWatts, power.aneWatts))
        }

        if model.fans.isEmpty {
            lines.append("Fans:       \(model.hasSMC ? "fanless (passive cooling)" : "unavailable")")
        } else {
            lines.append("Fans:       " + model.fans.map { "\(Int($0.rpm)) rpm" }.joined(separator: ", "))
        }

        if let battery = model.battery {
            var line = "Battery:    \(Int(battery.percent))%"
            line += battery.isCharging ? ", charging" : (battery.externalPower ? ", on power adapter" : ", on battery")
            if let health = battery.healthPercent { line += String(format: ", health %.0f%%", health) }
            if let cycles = battery.cycleCount { line += ", \(cycles) cycles" }
            lines.append(line)
        }

        if !model.topProcesses.isEmpty {
            lines.append("")
            lines.append("Top processes (CPU):")
            for process in model.topProcesses.prefix(5) {
                lines.append(String(format: "  %-26@ %5.1f%%", process.name as NSString, process.cpuPercent))
            }
        }

        return lines.joined(separator: "\n")
    }
}
