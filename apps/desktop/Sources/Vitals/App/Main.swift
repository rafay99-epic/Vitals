import Foundation
import AppKit

@main
enum Main {
    static func main() {
        let arguments = CommandLine.arguments

        // Intel Macs lack the M-series sensors and fan keys Vitals depends on.
        // The universal binary still launches there only to apologize.
        guard Hardware.isAppleSilicon else {
            MainActor.assumeIsolated { Hardware.showUnsupportedAndQuit() }
        }

        if arguments.contains("--probe") {
            runProbe()
        } else if arguments.contains("--check-update") {
            runUpdateCheck()
        } else if arguments.contains("--fan-daemon") {
            FanDaemon.run()
        } else if let index = arguments.firstIndex(of: "--fan-set") {
            runFanCommand(arguments: Array(arguments.dropFirst(index + 1)), auto: false)
        } else if let index = arguments.firstIndex(of: "--fan-auto") {
            runFanCommand(arguments: Array(arguments.dropFirst(index + 1)), auto: true)
        } else {
            // Single instance, like Activity Monitor: a second launch hands
            // off to the running app instead of starting a duplicate. The
            // fan daemon (activationPolicy .prohibited) doesn't count — it's
            // a background helper, not an app instance.
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

/// `Vitals --fan-set <index> <rpm>` / `Vitals --fan-auto <index>`.
/// Writing to the SMC requires root, so the app invokes its own binary with
/// these flags through an administrator-privileges prompt (FanController).
private func runFanCommand(arguments: [String], auto: Bool) {
    guard geteuid() == 0 else {
        print("error: fan control writes to the SMC and must run as root")
        exit(1)
    }
    guard let first = arguments.first, let fanIndex = Int(first) else {
        print("usage: Vitals --fan-set <index> <rpm> | --fan-auto <index>")
        exit(1)
    }
    guard let smc = SMC() else {
        print("error: could not open SMC")
        exit(1)
    }
    do {
        if auto {
            try smc.setFanAutomatic(fanIndex)
            print("fan \(fanIndex): automatic control restored")
        } else {
            guard arguments.count >= 2, let rpm = Double(arguments[1]) else {
                print("usage: Vitals --fan-set <index> <rpm>")
                exit(1)
            }
            let applied = try smc.setFanTarget(fanIndex, rpm: rpm)
            print("fan \(fanIndex): target set to \(Int(applied)) rpm")
        }
        exit(0)
    } catch {
        print("error: \(error.localizedDescription)")
        exit(1)
    }
}

/// `Vitals --check-update` queries GitHub Releases once and prints the
/// verdict — handy for testing the update pipeline without the GUI.
private func runUpdateCheck() {
    let semaphore = DispatchSemaphore(value: 0)
    Task {
        do {
            if let release = try await Updater.fetchLatestRelease() {
                print("Latest release: \(release.version) (\(release.assetName))")
                print("This build:     \(Updater.currentVersion)")
                print(Updater.isVersion(release.version, newerThan: Updater.currentVersion)
                    ? "→ update available"
                    : "→ up to date")
            } else {
                print("No releases published yet.")
            }
        } catch {
            print("Check failed: \(error.localizedDescription)")
        }
        semaphore.signal()
    }
    semaphore.wait()
}

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
    for process in processSampler.sample(top: 5) {
        print(String(format: "  %-30s %5.1f%%", (process.name as NSString).utf8String!, process.cpuPercent))
    }
}
