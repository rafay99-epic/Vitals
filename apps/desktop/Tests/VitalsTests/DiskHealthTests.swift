import Testing
import Foundation
@testable import Vitals

/// SSD health is read-only but accuracy-critical — a wrong wear/endurance figure
/// would needlessly scare someone about a soldered drive. Lock the pure decoders;
/// the live read just sanity-checks ranges (and skips cleanly with no SSD/SMART).
struct DiskHealthTests {
    @Test func dataUnitsConvertToBytes() {
        // NVMe spec: one data unit = 512,000 bytes.
        #expect(DiskHealthSnapshot.bytes(dataUnits: 0) == 0)
        #expect(DiskHealthSnapshot.bytes(dataUnits: 1) == 512_000)
        // 86,291,465 units ≈ 44.18 TB — a real reading from this machine.
        #expect(DiskHealthSnapshot.bytes(dataUnits: 86_291_465) == 44_181_230_080_000)
    }

    @Test func bytesClampInsteadOfOverflowing() {
        // An absurd/garbage counter must clamp, never wrap to a negative Int64.
        let huge = DiskHealthSnapshot.bytes(dataUnits: UInt64.max)
        #expect(huge == Int64.max)
        #expect(huge > 0)
    }

    @Test func conditionReadsTheCriticalWarningBitfield() {
        #expect(DiskHealthSnapshot.condition(criticalWarning: 0) == "Healthy")
        // Any set bit (spare exhausted, read-only, degraded…) is a real warning.
        #expect(DiskHealthSnapshot.condition(criticalWarning: 1) == "Service recommended")
        #expect(DiskHealthSnapshot.condition(criticalWarning: 0x10) == "Service recommended")
    }

    @Test func wearLevelFoldsInWarningAndSpareNotJustWear() {
        // A fresh, healthy drive is normal.
        #expect(make(percentUsed: 1, criticalWarning: 0, spare: 100, threshold: 10).wearLevel == .normal)
        // High wear escalates.
        #expect(make(percentUsed: 85).wearLevel == .elevated)
        #expect(make(percentUsed: 100).wearLevel == .critical)
        // A *low-wear* drive with the critical flag set must NOT read green —
        // the bug a wear-only tint would hide.
        #expect(make(percentUsed: 2, criticalWarning: 1).wearLevel == .critical)
        // Spare dipping below its threshold is at least elevated.
        #expect(make(percentUsed: 2, spare: 5, threshold: 10).wearLevel == .elevated)
    }

    @Test func poweredOnTextRollsOverToDaysAfterADay() {
        #expect(make(powerOnHours: 10).poweredOnText == "10 h")
        #expect(make(powerOnHours: 1012).poweredOnText == "42 days")
    }

    // A snapshot with only the fields a test cares about set.
    private func make(percentUsed: Int = 0, criticalWarning: Int = 0,
                      spare: Int = 100, threshold: Int = 10, powerOnHours: Int = 0) -> DiskHealthSnapshot {
        DiskHealthSnapshot(
            model: nil, capacityBytes: nil, percentUsed: percentUsed,
            bytesWritten: 0, bytesRead: 0, powerOnHours: powerOnHours, powerCycles: 0,
            unsafeShutdowns: 0, availableSpare: spare, availableSpareThreshold: threshold,
            mediaErrors: 0, temperature: nil, criticalWarning: criticalWarning
        )
    }

    @Test func liveReadStaysInSaneRanges() {
        // No internal SSD / no SMART (e.g. a VM) → nil; that's a valid outcome.
        guard let disk = DiskHealth.read() else { return }
        #expect(disk.percentUsed >= 0)
        #expect(disk.bytesWritten >= 0)
        #expect(disk.bytesRead >= 0)
        #expect(disk.powerOnHours >= 0)
        #expect(disk.availableSpare >= 0 && disk.availableSpare <= 100)
        if let temp = disk.temperature {
            #expect(temp > -40 && temp < 120)   // a plausible drive temperature
        }
    }
}
