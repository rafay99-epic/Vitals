import Testing
import Foundation
@testable import Vitals

/// Startup Impact shows the *live* resource cost of a login item — a real
/// footprint/CPU or an honest "Not running" — never a fabricated boot time.
/// These lock the exact `launchctl list` parse, the attribution state machine
/// (user agents judged running/idle, system items never guessed), and the
/// impact tiers.
struct StartupImpactTests {
    private func agent(_ label: String, kind: LaunchItem.Kind = .userAgent) -> LaunchItem {
        LaunchItem(label: label, program: "/usr/local/bin/\(label)",
                   plistPath: URL(fileURLWithPath: "/tmp/\(label).plist"),
                   kind: kind, runAtLoad: true, disabled: false)
    }

    // MARK: launchctl list parsing

    @Test func parseListKeepsRunningJobsAndSkipsHeaderAndIdle() {
        let text = """
        PID\tStatus\tLabel
        1234\t0\tcom.example.agent
        -\t0\tcom.example.idle
        77\t-9\tcom.example.crashedButRunning
        """
        let map = LaunchItemScanner.parseList(text)
        #expect(map["com.example.agent"] == 1234)
        #expect(map["com.example.crashedButRunning"] == 77)  // has a pid → running
        #expect(map["com.example.idle"] == nil)              // "-" → not running
        #expect(map["Label"] == nil)                         // header skipped by the pid guard
        #expect(map.count == 2)
    }

    @Test func parseListIsRobustToSpacesNotJustTabs() {
        // launchctl output should tab-delimit, but the parser tolerates spaces so
        // a formatting quirk can't silently drop every row.
        let text = "PID   Status  Label\n1234  0   com.example.agent\n-  0   com.example.idle"
        let map = LaunchItemScanner.parseList(text)
        #expect(map["com.example.agent"] == 1234)
        #expect(map["com.example.idle"] == nil)
        #expect(map.count == 1)
    }

    // MARK: Attribution state machine

    @Test func systemItemsAreNeverGuessed() {
        // The user-domain list isn't authoritative for the system domain, so even
        // with a matching pid a system item stays notMeasured — no false "idle".
        #expect(StartupImpact.state(for: agent("x", kind: .systemAgent), runningPIDs: [:]) == .notMeasured)
        #expect(StartupImpact.state(for: agent("x", kind: .systemDaemon),
                                    runningPIDs: ["x": 1234]) == .notMeasured)
    }

    @Test func userAgentAbsentFromListIsIdle() {
        #expect(StartupImpact.state(for: agent("com.test.idle"), runningPIDs: [:]) == .idle)
    }

    @Test func userAgentWithReadablePidIsRunningWithRealCost() {
        // Our own process is a readable pid → a real, non-zero footprint.
        let me = Int32(getpid())
        let state = StartupImpact.state(for: agent("com.test.me"), runningPIDs: ["com.test.me": me])
        guard case .running(let cost) = state else { Issue.record("expected running"); return }
        #expect(cost.memoryBytes > 0)
        #expect(cost.cpuSeconds >= 0)
    }

    @Test func userAgentWithUnreadablePidIsRunningButUnreadable() {
        // A pid that can't be read (here, one that doesn't exist) exercises the
        // "we know it's running but won't fabricate numbers" branch.
        let state = StartupImpact.state(for: agent("com.test.ghost"),
                                        runningPIDs: ["com.test.ghost": 2_000_000_000])
        #expect(state == .runningUnreadable)
    }

    // MARK: Impact tiers

    @Test func levelIsDrivenByFootprintWithHonestUnknowns() {
        func running(_ mb: Double) -> StartupImpact.State {
            .running(.init(memoryBytes: UInt64(mb * 1_048_576), cpuSeconds: 0))
        }
        #expect(StartupImpact.level(running(600)) == .high)
        #expect(StartupImpact.level(running(200)) == .medium)
        #expect(StartupImpact.level(running(50)) == .low)
        #expect(StartupImpact.level(.idle) == .idle)
        #expect(StartupImpact.level(.notMeasured) == .unknown)
        #expect(StartupImpact.level(.runningUnreadable) == .unknown)
    }

    // MARK: Direct cost read

    @Test func readCostReadsOwnProcess() {
        let cost = StartupImpact.readCost(pid: Int32(getpid()))
        #expect(cost != nil)
        #expect((cost?.memoryBytes ?? 0) > 0)
        #expect((cost?.cpuSeconds ?? -1) >= 0)
    }
}
