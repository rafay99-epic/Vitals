import Foundation
import AppKit

@main
enum Main {
    static func main() {
        let arguments = CommandLine.arguments

        if arguments.contains("--probe") {
            runProbe()
        } else if arguments.contains("--fan-daemon") {
            FanHelperRetirement.runAsHelper()
        } else {
            // Single instance, like Activity Monitor: a second launch hands
            // off to the running app instead of starting a duplicate. A
            // retiring fan helper (activationPolicy .prohibited) doesn't count.
            let myPID = NSRunningApplication.current.processIdentifier
            if let bundleID = Bundle.main.bundleIdentifier,
               let other = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                   .first(where: { $0.processIdentifier != myPID && $0.activationPolicy != .prohibited }) {
                other.activate(options: [.activateAllWindows])
                exit(0)
            }
            VitalsApp.main()
        }
    }
}

// MARK: - CLI tools

/// `Vitals --probe` prints one round of raw readings to stdout and exits.
/// Useful for sanity-checking the sensors without launching the GUI.
private func runProbe() {
    print("== Vitals probe ==")
    print(HardwareInfo.chipName, "·", HardwareInfo.osVersion)

    let readings = HIDSensors().readAll()
    print("\n\(readings.count) temperature sensors:")
    for reading in readings.sorted(by: { $0.name < $1.name }) {
        print(String(format: "  %-36s %6.2f °C", (reading.name as NSString).utf8String!, reading.celsius))
    }

    if let smc = SMC() {
        let fans = smc.fans()
        print("\n\(fans.count) fans:")
        for fan in fans {
            let mode = fan.isManual.map { $0 ? "manual" : "auto" } ?? "unknown"
            let rawMode = smc.read("F\(fan.id)Md").map { String($0) } ?? "n/a"
            print("  Fan \(fan.id): \(Int(fan.rpm)) rpm, \(mode) [F\(fan.id)Md=\(rawMode)] (target \(Int(fan.targetRPM)), range \(Int(fan.minRPM))–\(Int(fan.maxRPM)))")
        }
    } else {
        print("\nSMC: connection failed")
    }

    if let memory = MemoryStats.read() {
        print(String(format: "\nMemory: %.1f / %.0f GB used (app %.1f, wired %.1f, compressed %.1f, cached %.1f)",
                     gigabytes(memory.used), gigabytes(memory.total),
                     gigabytes(memory.app), gigabytes(memory.wired),
                     gigabytes(memory.compressed), gigabytes(memory.cached)))
        print(String(format: "Swap: %.2f / %.1f GB · pressure %@",
                     gigabytes(memory.swapUsed), gigabytes(memory.swapTotal), memory.pressure.label))
    }

    if let battery = Battery.read() {
        print(String(
            format: "\nBattery: %.0f%%, health %@, %@ cycles, %@",
            battery.percent,
            battery.healthPercent.map { String(format: "%.0f%%", $0) } ?? "n/a",
            battery.cycleCount.map(String.init) ?? "n/a",
            battery.isCharging ? "charging" : (battery.externalPower ? "on AC" : "on battery")
        ))
    } else {
        print("\nBattery: not found")
    }

    let processSampler = ProcessSampler()
    _ = processSampler.sample(top: 5)
    Thread.sleep(forTimeInterval: 1.0)
    print("\nTop processes:")
    for process in processSampler.sample(top: 5).byCPU {
        print(String(format: "  %-30s %5.1f%%", (process.name as NSString).utf8String!, process.cpuPercent))
    }
}
