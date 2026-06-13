import XCTest
@testable import VitalsCore

final class HwmonTests: XCTestCase {

    func testParsesTempsAndFanFromCoretemp() {
        let files = [
            "temp1_input": "45000\n",
            "temp1_label": "Package id 0\n",
            "temp2_input": "43000",
            "temp2_label": "Core 0",
            "fan1_input": "1200"
        ]
        let (temps, fans) = Hwmon.parse(chip: "coretemp", files: files)
        XCTAssertEqual(temps.count, 2)
        XCTAssertEqual(temps.first { $0.label == "Package id 0" }?.celsius, 45)
        XCTAssertEqual(temps.first { $0.label == "Core 0" }?.celsius, 43)
        XCTAssertTrue(temps.allSatisfy { $0.kind == .cpu })
        XCTAssertEqual(fans, [FanReading(label: "Fan 1", rpm: 1200)])
    }

    func testFanlessHardwareYieldsNoFans() {
        let (_, fans) = Hwmon.parse(chip: "coretemp", files: ["temp1_input": "40000"])
        XCTAssertTrue(fans.isEmpty, "no fan*_input must mean no fans, never a fabricated 0 rpm")
    }

    func testStoppedFanReportedHonestly() {
        let (_, fans) = Hwmon.parse(chip: "nct6779", files: ["fan1_input": "0"])
        XCTAssertEqual(fans, [FanReading(label: "Fan 1", rpm: 0)], "0 rpm is a real reading, kept as-is")
    }

    func testClassification() {
        XCTAssertEqual(Hwmon.classify(chip: "k10temp", label: "Tdie"), .cpu)
        XCTAssertEqual(Hwmon.classify(chip: "amdgpu", label: "edge"), .gpu)
        XCTAssertEqual(Hwmon.classify(chip: "nvme", label: "Composite"), .storage)
        XCTAssertEqual(Hwmon.classify(chip: "BAT0", label: nil), .battery)
        XCTAssertEqual(Hwmon.classify(chip: "acpitz", label: nil), .other)
    }
}

final class ProcStatTests: XCTestCase {

    func testParseAggregate() {
        let ticks = ProcStat.parseAggregate("cpu  100 0 50 1000 20 0 0 0 0 0\ncpu0 50 0 25 500 10 0 0 0 0 0\n")
        XCTAssertEqual(ticks, ProcStat.Ticks(total: 1170, idle: 1020))   // idle 1000 + iowait 20
    }

    func testUsageBetweenSamples() {
        // 100 total ticks elapsed, 20 of them idle → 80% busy.
        let usage = ProcStat.usage(
            previous: ProcStat.Ticks(total: 1000, idle: 900),
            current: ProcStat.Ticks(total: 1100, idle: 920)
        )
        XCTAssertEqual(usage ?? -1, 80, accuracy: 0.001)
    }

    func testNoElapsedTimeReturnsNil() {
        let t = ProcStat.Ticks(total: 1000, idle: 900)
        XCTAssertNil(ProcStat.usage(previous: t, current: t))
    }
}

final class MeminfoTests: XCTestCase {

    private let fixture = """
    MemTotal:       16384000 kB
    MemFree:         1000000 kB
    MemAvailable:    8000000 kB
    Cached:          4000000 kB
    SwapTotal:       2000000 kB
    SwapFree:        1500000 kB
    """

    func testParseUsesAvailableForUsed() {
        let m = Meminfo.parse(fixture)
        XCTAssertEqual(m?.total, 16_384_000 * 1024)
        XCTAssertEqual(m?.available, 8_000_000 * 1024)
        XCTAssertEqual(m?.used, (16_384_000 - 8_000_000) * 1024)
        XCTAssertEqual(m?.swapUsed, (2_000_000 - 1_500_000) * 1024)
    }

    func testPressureLevels() {
        XCTAssertEqual(Meminfo.parsePressure("some avg10=0.00 avg60=0.0 total=1\nfull avg10=0.00 avg60=0.0 total=1"), .normal)
        XCTAssertEqual(Meminfo.parsePressure("some avg10=2.50 avg60=1.0 total=1\nfull avg10=0.00 avg60=0.0 total=1"), .warning)
        XCTAssertEqual(Meminfo.parsePressure("some avg10=40.0 avg60=1.0 total=1\nfull avg10=15.0 avg60=2.0 total=1"), .critical)
    }

    func testPressureNilWhenUnavailable() {
        XCTAssertNil(Meminfo.parsePressure(""), "no PSI → no pressure shown, not a guess")
    }
}

final class PowerSupplyTests: XCTestCase {

    func testEnergyBatteryDischarging() {
        let b = PowerSupply.parseBattery(files: [
            "capacity": "80",
            "status": "Discharging",
            "energy_full": "50000000",
            "energy_full_design": "56000000",
            "power_now": "8000000",
            "cycle_count": "120"
        ], acOnline: false)
        XCTAssertEqual(b?.percent, 80)
        XCTAssertFalse(b?.isCharging ?? true)
        XCTAssertEqual(b?.healthPercent ?? 0, 50.0 / 56.0 * 100, accuracy: 0.01)
        XCTAssertEqual(b?.watts ?? 0, -8, accuracy: 0.001, "discharging is negative")
        XCTAssertEqual(b?.cycleCount, 120)
    }

    func testChargeBatteryFromCurrentVoltage() {
        let b = PowerSupply.parseBattery(files: [
            "capacity": "55",
            "status": "Charging",
            "charge_full": "4000000",
            "charge_full_design": "5000000",
            "current_now": "1000000",
            "voltage_now": "12000000"
        ], acOnline: true)
        XCTAssertEqual(b?.healthPercent ?? 0, 80, accuracy: 0.01)
        XCTAssertEqual(b?.watts ?? 0, 12, accuracy: 0.001, "charging is positive")
        XCTAssertTrue(b?.isCharging ?? false)
    }

    func testDesktopWithoutBatteryIsNil() {
        XCTAssertNil(PowerSupply.parseBattery(files: ["status": "Unknown"], acOnline: true),
                     "no capacity → no battery, never a fake 100%")
    }
}

final class ProcessTests: XCTestCase {

    func testParseTicksWithSimpleComm() {
        // utime (field 14) = 12, stime (field 15) = 34.
        let stat = "1234 (bash) S 1 1234 1234 0 -1 4194304 100 0 0 0 12 34 0 0 20 0 1 0 9876"
        XCTAssertEqual(ProcPidStat.parseCPUTicks(stat), 46)
    }

    func testParseTicksWithParensInComm() {
        // comm contains spaces and ')' — fields counted from the LAST ')'.
        let stat = "42 (weird )name)) S 1 42 42 0 -1 4194304 5 0 0 0 7 8 0 0 20 0 1 0 100"
        XCTAssertEqual(ProcPidStat.parseCPUTicks(stat), 15)
    }

    func testCPUPercent() {
        // 100 ticks at 100 Hz over 1 s = one core fully busy.
        XCTAssertEqual(ProcPidStat.cpuPercent(deltaTicks: 100, wallSeconds: 1, clockTicks: 100), 100, accuracy: 0.001)
        XCTAssertEqual(ProcPidStat.cpuPercent(deltaTicks: 50, wallSeconds: 1, clockTicks: 100), 50, accuracy: 0.001)
    }
}

final class CPUInfoTests: XCTestCase {

    func testX86ModelName() {
        let cpuinfo = "processor\t: 0\nvendor_id\t: GenuineIntel\nmodel name\t: Intel(R) Core(TM) i7-9750H\n"
        XCTAssertEqual(CPUInfo.parseModelName(cpuinfo), "Intel(R) Core(TM) i7-9750H")
    }

    func testARMFallbackToHardware() {
        let cpuinfo = "processor\t: 0\nBogoMIPS\t: 108.00\nHardware\t: BCM2835\n"
        XCTAssertEqual(CPUInfo.parseModelName(cpuinfo), "BCM2835")
    }

    func testNoNameReturnsNil() {
        XCTAssertNil(CPUInfo.parseModelName("processor\t: 0\n"))
    }
}
