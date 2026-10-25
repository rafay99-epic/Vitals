import Testing
import Foundation
@testable import Vitals

struct BridgeFixtureTests {
    private static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("../../packages/contracts/fixtures/bridge")
        .standardizedFileURL

    private func fixture(_ name: String) throws -> [Any] {
        let data = try Data(contentsOf: Self.fixtures.appendingPathComponent(name))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [Any])
    }

    private func encoded(_ message: FromApp) throws -> NSDictionary {
        let data = try JSONEncoder().encode(message)
        return try #require(try JSONSerialization.jsonObject(with: data) as? NSDictionary)
    }

    @Test func everyGatewayMessageDecodes() throws {
        for entry in try fixture("to-app.json") {
            let data = try JSONSerialization.data(withJSONObject: entry)
            _ = try JSONDecoder().decode(ToApp.self, from: data)
        }
    }

    @Test func commandsDecodeToTheirCases() throws {
        let line = #"{"t":"cmd","id":"c","deviceId":"d","deviceName":"P","command":{"_tag":"Processes","actions":[{"target":{"pid":42,"startTimeMs":7},"action":"pause"}]}}"#
        let message = try JSONDecoder().decode(ToApp.self, from: Data(line.utf8))
        #expect(message == .command(id: "c", deviceId: "d", deviceName: "P", command: .processes([
            ProcessAction(target: ProcessRef(pid: 42, startTimeMs: 7), action: .pause)
        ])))
    }

    @Test func appMessagesMatchTheContractFixtures() throws {
        let expected = try fixture("from-app.json").compactMap { $0 as? NSDictionary }
        let receipt = FromApp.receipt(WireReceipt(
            id: "cmd-1", kind: "ShutDown", deviceId: "dev-1", status: .pending,
            createdAt: 1_790_000_000_000, deadlineAt: 1_790_000_010_000, finishedAt: nil, error: nil
        ))
        #expect(try encoded(receipt) == expected[5])
        #expect(try encoded(.event(.willSleep(at: 1_790_000_000_000))) == expected[6])
        #expect(try encoded(.event(.thermalChanged(at: 1_790_000_000_000, state: "serious"))) == expected[7])
        let keepAwake = WireKeepAwake(active: true, display: false, until: nil, whileProcess: ProcessRef(pid: 4242, startTimeMs: 1_789_990_000_000))
        #expect(try encoded(.event(.keepAwakeChanged(at: 1_790_000_000_000, state: keepAwake))) == expected[8])
        #expect(try encoded(.result(id: "q-3", ok: nil, error: "clipboard unavailable")) == expected[11])
        #expect(try encoded(.admin(id: "a-1", op: .createPairing)) == expected[12])
        #expect(try encoded(.admin(id: "a-3", op: .setScopes(deviceId: "dev-1", scopes: ["read", "operate", "destructive"]))) == expected[13])
    }

    @Test func fullSampleMatchesTheContractFixture() throws {
        let expected = try #require(try fixture("from-app.json").compactMap { $0 as? NSDictionary }.last)
        var sample = WireSample(seq: 9, at: 1_790_000_002_000)
        sample.gpu = WireGPU(utilization: 18, memoryUsedBytes: 6_200_000_000, coreCount: 40,
                             rendererUtilization: 16, tilerUtilization: 9, memoryTotalBytes: 27_000_000_000)
        sample.battery = Nullable(wrappedValue: WireBattery(
            percent: 82, charging: true, externalPower: true, watts: 36.1, timeRemainingMinutes: 38, cycleCount: 214,
            healthPercent: 91, temperatureC: 31, condition: "Normal", fullyCharged: false, designCapacityMah: 7594,
            maxCapacityMah: 6912, voltage: 12.71, amperage: 2.84,
            adapter: WireAdapter(watts: 96, name: "96W USB-C Power Adapter", wireless: false, deliveredWatts: 41.2, voltage: 20, amperage: 2.06)
        ))
        sample.network = WireNetwork(
            inBytesPerSec: 2_100_000, outBytesPerSec: 340_000, wifiRssi: -54, primaryInterface: "en0",
            totalInBytes: 48_200_000_000, totalOutBytes: 6_100_000_000,
            links: [WireLink(name: "en0", label: "Wi-Fi", kind: "wifi", inBytesPerSec: 2_100_000, outBytesPerSec: 340_000, active: true)],
            wifi: WireWifi(ssid: "Home-5G", rssi: -54, noise: -92, txRateMbps: 1201, channel: 149, band: "5 GHz")
        )
        sample.disk = WireDisk(
            readBytesPerSec: 84_000_000, writeBytesPerSec: 12_000_000, freeBytes: 412_000_000_000, totalBytes: 994_000_000_000,
            volume: "Macintosh HD",
            health: WireDriveHealth(model: "APPLE SSD AP1024Z", wearPercent: 3, readBytes: 61_200_000_000_000,
                                    writtenBytes: 38_400_000_000_000, powerOnHours: 2140, unsafeShutdowns: 6,
                                    sparePercent: 100, celsius: 41, warning: false)
        )
        #expect(try encoded(.sample(sample)) == expected)
    }

    @Test func unreadExtrasAreOmitted() throws {
        var sample = WireSample(seq: 1, at: 5)
        sample.disk = WireDisk(readBytesPerSec: 0, writeBytesPerSec: 0)
        let json = try encoded(.sample(sample))
        let disk = try #require((json["data"] as? NSDictionary)?["disk"] as? NSDictionary)
        #expect(disk.allKeys.count == 2)
    }

    @Test func missingReadingsEncodeAsNullNotZero() throws {
        var sample = WireSample(seq: 1, at: 5)
        sample.cpu = WireCPU(overall: nil, performance: nil, efficiency: nil, perCore: [])
        sample.power = Nullable(wrappedValue: nil)
        let json = try encoded(.sample(sample))
        let data = try #require(json["data"] as? NSDictionary)
        let cpu = try #require(data["cpu"] as? NSDictionary)
        #expect(cpu["overall"] is NSNull)
        #expect(data["power"] is NSNull)
        #expect(data["memory"] == nil)
    }
}

@MainActor
private final class RecordingExecutor: CommandExecutor {
    var executed: [RemoteCommand] = []
    var failWith: String?

    func execute(_ command: RemoteCommand) async -> String? {
        executed.append(command)
        return failWith
    }
}

@MainActor
struct CommandRouterTests {
    private func request(_ id: String, _ command: RemoteCommand) -> CommandRouter.Request {
        .init(id: id, deviceId: "dev", deviceName: "Pixel", command: command)
    }

    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    @Test func immediateCommandsRunOnceAndAreIdempotent() async {
        let executor = RecordingExecutor()
        let router = CommandRouter(executor: executor)
        var receipts: [WireReceipt] = []
        router.onReceipt = { receipts.append($0) }
        router.run(request("a", .setMuted(true)))
        await settle()
        router.run(request("a", .setMuted(true)))
        await settle()
        #expect(executor.executed == [.setMuted(true)])
        #expect(receipts.map(\.status) == [.done, .done])
    }

    @Test func duplicateDeliveryWhileRunningExecutesOnce() async {
        let executor = RecordingExecutor()
        let router = CommandRouter(executor: executor)
        var receipts: [WireReceipt] = []
        router.onReceipt = { receipts.append($0) }
        router.run(request("b", .setMuted(false)))
        router.run(request("b", .setMuted(false)))
        await settle()
        #expect(executor.executed == [.setMuted(false)])
        #expect(receipts.map(\.status) == [.running, .done])
    }

    @Test func graceCommandIsNotRerunAfterItFires() async {
        let executor = RecordingExecutor()
        let router = CommandRouter(executor: executor)
        router.run(request("r", .sleep(grace: 10)))
        router.fireNow("r")
        router.run(request("r", .sleep(grace: 10)))
        await settle()
        #expect(executor.executed == [.sleep(grace: 10)])
        #expect(router.pendingIds.isEmpty)
    }

    @Test func graceCommandsWaitAndCanBeCancelled() async {
        let executor = RecordingExecutor()
        let router = CommandRouter(executor: executor)
        var receipts: [WireReceipt] = []
        var graceStarted = false
        router.onReceipt = { receipts.append($0) }
        router.onGraceStarted = { _, _ in graceStarted = true }
        router.run(request("s", .shutDown(grace: 10)))
        #expect(graceStarted)
        #expect(receipts.last?.status == .pending)
        #expect(receipts.last?.deadlineAt != nil)
        router.cancel("s")
        await settle()
        #expect(executor.executed.isEmpty)
        #expect(receipts.last?.status == .cancelled)
        #expect(router.pendingIds.isEmpty)
    }

    @Test func powerOffAnnouncesBeforeExecuting() async {
        let executor = RecordingExecutor()
        let router = CommandRouter(executor: executor)
        var announced = false
        var statuses: [WireReceipt.Status] = []
        router.onReceipt = { statuses.append($0.status) }
        router.onWillPowerOff = { announced = true }
        router.run(request("r", .restart(grace: 10)))
        router.fireNow("r")
        await settle()
        #expect(announced)
        #expect(executor.executed == [.restart(grace: 10)])
        #expect(statuses == [.pending, .running, .done])
    }

    @Test func failuresCarryTheReason() async {
        let executor = RecordingExecutor()
        executor.failWith = "App is no longer running"
        let router = CommandRouter(executor: executor)
        var last: WireReceipt?
        router.onReceipt = { last = $0 }
        router.run(request("q", .quitApp(AppRef(pid: 9, bundleId: nil))))
        await settle()
        #expect(last?.status == .failed)
        #expect(last?.error == "App is no longer running")
    }
}

struct PressureGuardTests {
    private static let start = Date(timeIntervalSince1970: 1_790_000_000)

    private func inputs(at offset: TimeInterval, pressure: Int, rows: [ProcessSampler.Row] = []) -> PressureGuard.Inputs {
        PressureGuard.Inputs(
            now: Self.start.addingTimeInterval(offset),
            pressureLevel: pressure,
            swapUsed: 0,
            cpuPercent: 10,
            thermalLevel: 0,
            memoryTotal: 16 << 30,
            classified: ProcessGroups.classify(rows, ownUid: 501, ownPid: 9999),
            table: rows
        )
    }

    @Test func criticalPressureRaisesAfterHoldAndClearsAfterHysteresis() {
        var engine = PressureGuard(settings: PressureGuard.defaultSettings)
        #expect(engine.evaluate(inputs(at: 0, pressure: 2)).isEmpty)
        let raised = engine.evaluate(inputs(at: 10, pressure: 2))
        guard case let .raised(alert)? = raised.first else {
            Issue.record("expected a raised alert")
            return
        }
        #expect(alert.rule == "memoryPressure")
        #expect(alert.severity == "critical")
        #expect(engine.evaluate(inputs(at: 20, pressure: 0)).isEmpty)
        let cleared = engine.evaluate(inputs(at: 81, pressure: 0))
        #expect(cleared.count == 1)
        #expect(engine.active.isEmpty)
    }

    @Test func cooldownStopsAlertSpam() {
        var engine = PressureGuard(settings: PressureGuard.defaultSettings)
        _ = engine.evaluate(inputs(at: 0, pressure: 2))
        _ = engine.evaluate(inputs(at: 10, pressure: 2))
        _ = engine.evaluate(inputs(at: 11, pressure: 0))
        _ = engine.evaluate(inputs(at: 80, pressure: 0))
        _ = engine.evaluate(inputs(at: 81, pressure: 2))
        #expect(engine.evaluate(inputs(at: 100, pressure: 2)).isEmpty)
    }

    @Test func calmPlanThrottlesAgentsAndPausesIdleEmulators() {
        let rows = [
            row(pid: 10, ppid: 1, name: "claude", cpu: 80),
            row(pid: 11, ppid: 10, name: "node", cpu: 20),
            row(pid: 20, ppid: 1, name: "qemu-system-aarch64", cpu: 1),
            row(pid: 21, ppid: 1, name: "qemu-system-aarch64", cpu: 60),
            row(pid: 30, ppid: 1, name: "node", cpu: 5)
        ]
        let classified = ProcessGroups.classify(rows, ownUid: 501, ownPid: 9999)
        let plan = PressureGuard.calmPlan(rows, classified: classified)
        let byPid = Dictionary(uniqueKeysWithValues: plan.actions.map { ($0.target.pid, $0.action) })
        #expect(byPid[10] == .throttle)
        #expect(byPid[11] == .throttle)
        #expect(byPid[20] == .pause)
        #expect(byPid[21] == nil)
        #expect(byPid[30] == nil)
    }

    private func row(pid: pid_t, ppid: pid_t, name: String, cpu: Double, uid: uid_t = 501) -> ProcessSampler.Row {
        ProcessSampler.Row(pid: pid, ppid: ppid, uid: uid, startTimeMs: Int64(pid), name: name, path: "/usr/local/bin/\(name)", cpuPercent: cpu, memory: 100)
    }
}

struct ProcessGroupsTests {
    @Test func classifiesByNameAncestryAndOwner() {
        let rows = [
            ProcessSampler.Row(pid: 100, ppid: 1, uid: 501, startTimeMs: 1, name: "codex", path: "/opt/codex", cpuPercent: 1, memory: 10),
            ProcessSampler.Row(pid: 101, ppid: 100, uid: 501, startTimeMs: 1, name: "node", path: "/opt/node", cpuPercent: 1, memory: 10),
            ProcessSampler.Row(pid: 200, ppid: 1, uid: 501, startTimeMs: 1, name: "node", path: "/opt/node", cpuPercent: 1, memory: 10),
            ProcessSampler.Row(pid: 300, ppid: 1, uid: 0, startTimeMs: 1, name: "codex", path: "/opt/codex", cpuPercent: 1, memory: 10),
            ProcessSampler.Row(pid: 400, ppid: 1, uid: 501, startTimeMs: 1, name: "Finder", path: "/System/Library/CoreServices/Finder.app", cpuPercent: 1, memory: 10),
            ProcessSampler.Row(pid: 500, ppid: 1, uid: 501, startTimeMs: 1, name: "Google Chrome Helper", path: "/Applications/Google Chrome.app", cpuPercent: 1, memory: 10),
            ProcessSampler.Row(pid: 600, ppid: 1, uid: 501, startTimeMs: 1, name: "T3 Code (Nightly)", path: "/Applications/T3 Code (Nightly).app/Contents/MacOS/T3 Code (Nightly)", cpuPercent: 1, memory: 10),
            ProcessSampler.Row(pid: 601, ppid: 600, uid: 501, startTimeMs: 1, name: "claude 2.1.303", path: "/Users/me/.local/share/claude/versions/2.1.303", cpuPercent: 1, memory: 10),
            ProcessSampler.Row(pid: 602, ppid: 601, uid: 501, startTimeMs: 1, name: "node", path: "/opt/node", cpuPercent: 1, memory: 10)
        ]
        let classified = ProcessGroups.classify(rows, ownUid: 501, ownPid: 9999)
        #expect(classified.group(of: 100) == .agents)
        #expect(classified.group(of: 101) == .agents)
        #expect(classified.group(of: 200) == .devServers)
        #expect(classified.group(of: 300) == .protected)
        #expect(classified.group(of: 400) == .protected)
        #expect(classified.group(of: 500) == .browsers)
        #expect(classified.group(of: 600) == .other)
        #expect(classified.group(of: 601) == .agents)
        #expect(classified.group(of: 602) == .agents)
        #expect(classified.group(of: 9_999) == .protected)
        #expect(classified.totals(for: .agents).count == 4)
    }
}

struct ProcessControlTests {
    @Test func pausesResumesAndStopsOnlyTheExactProcess() throws {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["30"]
        try child.run()
        defer { if child.isRunning { child.terminate() } }
        let pid = child.processIdentifier
        let start = try #require(ProcessSampler.startTimeMs(of: pid))
        let ref = ProcessRef(pid: pid, startTimeMs: start)

        #expect(ProcessControl.apply(ProcessAction(target: ProcessRef(pid: pid, startTimeMs: start + 1), action: .pause), isProtected: { _ in false }) == .gone)
        #expect(ProcessControl.apply(ProcessAction(target: ref, action: .pause), isProtected: { _ in true }) == .protected)
        #expect(ProcessControl.apply(ProcessAction(target: ref, action: .throttle), isProtected: { _ in false }) == nil)
        #expect(ProcessControl.apply(ProcessAction(target: ref, action: .pause), isProtected: { _ in false }) == nil)
        #expect(state(of: pid).hasPrefix("T"))
        #expect(ProcessControl.apply(ProcessAction(target: ref, action: .resume), isProtected: { _ in false }) == nil)
        #expect(!state(of: pid).hasPrefix("T"))
        #expect(ProcessControl.apply(ProcessAction(target: ref, action: .terminate), isProtected: { _ in false }) == nil)
        child.waitUntilExit()
        #expect(ProcessControl.apply(ProcessAction(target: ref, action: .kill), isProtected: { _ in false }) == .gone)
    }

    @Test func refusesItsOwnProcess() {
        let own = ProcessRef(pid: getpid(), startTimeMs: ProcessSampler.startTimeMs(of: getpid()) ?? 0)
        #expect(ProcessControl.apply(ProcessAction(target: own, action: .pause), isProtected: { _ in false }) == .protected)
    }

    private func state(of pid: pid_t) -> String {
        let ps = Process()
        let pipe = Pipe()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-o", "stat=", "-p", "\(pid)"]
        ps.standardOutput = pipe
        try? ps.run()
        ps.waitUntilExit()
        return (String(bytes: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
