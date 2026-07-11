import Testing
import Foundation
@testable import Vitals

/// Locks the per-process energy math: a real energy delta becomes watts, a
/// non-advancing counter yields no wattage (so we never invent a reading), and
/// the Energy-Impact fallback ranks by CPU + wakeups.
struct AppEnergyTests {
    private let oneSecond = 1_000_000_000.0   // nanoseconds

    @Test func energyDeltaBecomesWatts() {
        // 5 J over 1 s == 5 W. 5 J == 5e9 nJ.
        let watts = EnergyRate.watts(energyDeltaNanojoules: 5_000_000_000, overNanoseconds: oneSecond)
        #expect(watts != nil)
        #expect(abs(watts! - 5.0) < 0.0001)
    }

    @Test func halfSecondIntervalDoublesPower() {
        // 5 J over 0.5 s == 10 W.
        let watts = EnergyRate.watts(energyDeltaNanojoules: 5_000_000_000, overNanoseconds: oneSecond / 2)
        #expect(abs(watts! - 10.0) < 0.0001)
    }

    @Test func noEnergyMeansNoWattage() {
        // OS reported no energy for this process — must be nil, not 0 W invented.
        #expect(EnergyRate.watts(energyDeltaNanojoules: 0, overNanoseconds: oneSecond) == nil)
        // Non-positive interval is also nil.
        #expect(EnergyRate.watts(energyDeltaNanojoules: 100, overNanoseconds: 0) == nil)
    }

    @Test func wakeupsPerSecond() {
        #expect(abs(EnergyRate.perSecond(delta: 300, overNanoseconds: oneSecond) - 300) < 0.0001)
        #expect(abs(EnergyRate.perSecond(delta: 300, overNanoseconds: oneSecond * 2) - 150) < 0.0001)
        #expect(EnergyRate.perSecond(delta: 10, overNanoseconds: 0) == 0)
    }

    @Test func impactIndexRanksByCPUAndWakeups() {
        let busy = EnergyRate.impactIndex(cpuPercent: 50, wakeupsPerSec: 0)
        let chatty = EnergyRate.impactIndex(cpuPercent: 0, wakeupsPerSec: 200)
        let idle = EnergyRate.impactIndex(cpuPercent: 0, wakeupsPerSec: 0)
        #expect(idle == 0)
        #expect(busy > idle)
        #expect(chatty > idle)
    }

    @Test func groupingFoldsHelpersUnderTheApp() {
        let brave = URL(fileURLWithPath: "/Applications/Brave.app")
        let procs = [
            RunningProcess(id: 1, name: "Brave", executablePath: "/Applications/Brave.app/Contents/MacOS/Brave",
                           bundleURL: brave, memoryBytes: 100, cpuPercent: 10, avgWatts: 1.0, wakeupsPerSec: 5, ownedByCurrentUser: true),
            RunningProcess(id: 2, name: "Brave Helper", executablePath: "/Applications/Brave.app/Contents/Frameworks/Brave Helper",
                           bundleURL: brave, memoryBytes: 50, cpuPercent: 4, avgWatts: 0.5, wakeupsPerSec: 3, ownedByCurrentUser: true),
            RunningProcess(id: 3, name: "sshd", executablePath: "/usr/sbin/sshd",
                           bundleURL: nil, memoryBytes: 20, cpuPercent: 1, avgWatts: nil, wakeupsPerSec: 1, ownedByCurrentUser: false),
        ]
        let rows = groupProcessesByApp(procs, groupHelpers: true) { key, lead, items in
            (name: lead.name, watts: items.reduce(0.0) { $0 + ($1.avgWatts ?? 0) }, count: items.count)
        }
        #expect(rows.count == 2)                       // Brave (folded) + sshd
        #expect(rows[0].name == "Brave")
        #expect(rows[0].count == 2)
        #expect(abs(rows[0].watts - 1.5) < 0.0001)     // helper power summed into the app
    }
}
