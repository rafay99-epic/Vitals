import Foundation
import AppKit

@MainActor
@Observable
final class RemoteModel {
    enum GatewayState: Equatable {
        case off
        case starting
        case running
        case restarting(attempt: Int)
        case failed(String)
    }

    struct Pairing: Equatable {
        let code: String
        let url: String?
        let expiresAt: Date
    }

    private(set) var state: GatewayState = .off
    private(set) var status: GatewayStatus?
    private(set) var devices: [RemoteDevice] = []
    private(set) var pairing: Pairing?
    private(set) var keepAwake = PowerControl.KeepAwake()
    private(set) var guardState: WireGuardState?
    struct PendingCommand: Equatable {
        let deviceName: String
        let kind: String
        let deadline: Date
    }

    private(set) var pendingCommands: [String: PendingCommand] = [:]
    private(set) var adminError: String?

    var isEnabled: Bool { settings.remoteEnabled }

    @ObservationIgnored private let vitals: VitalsModel
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let power = PowerControl()
    @ObservationIgnored private lazy var router = CommandRouter(executor: SystemCommandExecutor(model: self))
    @ObservationIgnored private var gateway: GatewayProcess?
    @ObservationIgnored private var restartTask: Task<Void, Never>?
    @ObservationIgnored private var restartAttempt = 0
    @ObservationIgnored private var gatewayGeneration = 0
    @ObservationIgnored private var startedAt: Date?
    @ObservationIgnored private var needs = NeedsMessage.none
    @ObservationIgnored private var sampleSeq = 0
    @ObservationIgnored private var adminWaiters: [String: CheckedContinuation<AdminResult, Error>] = [:]
    @ObservationIgnored private var guardEngine: PressureGuard
    @ObservationIgnored private var latestTable: [ProcessSampler.Row] = []
    @ObservationIgnored private var latestClassified = ProcessGroups.classify([])
    @ObservationIgnored private var throttled: Set<ProcessRef> = []
    @ObservationIgnored private var paused: Set<ProcessRef> = []
    @ObservationIgnored private var calmActions: [ProcessAction] = []
    @ObservationIgnored private var lastGuardSent: WireGuardState?
    @ObservationIgnored private var lastThermal = ProcessInfo.processInfo.thermalState
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    struct AdminFailure: Error, Equatable { let message: String }

    init(vitals: VitalsModel, settings: AppSettings) {
        self.vitals = vitals
        self.settings = settings
        guardEngine = PressureGuard(settings: settings.guardSettings)
        power.onKeepAwakeChange = { [weak self] state in self?.keepAwakeChanged(state) }
        vitals.onSampled = { [weak self] table in self?.sampled(table) }
        NotificationManager.shared.onRemoteAction = { [weak self] action in self?.handleNotificationAction(action) }
        configureRouter()
        updateVitalsNeeds()
        let workspace = NSWorkspace.shared.notificationCenter
        observers = [
            workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.send(.event(.willSleep(at: Self.now()))) }
            },
            workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.send(.event(.didWake(at: Self.now()))) }
            },
            NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.shutdown() }
            }
        ]
        if settings.remoteEnabled { startGateway() }
    }

    deinit {
        observers.forEach {
            NSWorkspace.shared.notificationCenter.removeObserver($0)
            NotificationCenter.default.removeObserver($0)
        }
    }

    func setEnabled(_ enabled: Bool) {
        guard settings.remoteEnabled != enabled else { return }
        settings.remoteEnabled = enabled
        if enabled {
            restartAttempt = 0
            startGateway()
            log("info", "desktop.remote.toggled", ["enabled": .bool(true)])
        } else {
            stopGateway()
        }
    }

    func shutdown() {
        power.stopKeepAwake(notify: false)
        stopGateway()
    }

    // MARK: Gateway lifecycle

    static var gatewayExecutable: URL? {
        if let override = ProcessInfo.processInfo.environment["VITALS_GATEWAY_PATH"] {
            return URL(fileURLWithPath: override)
        }
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/vitals-gateway")
        return FileManager.default.isExecutableFile(atPath: bundled.path) ? bundled : nil
    }

    static var webDirectory: URL? {
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/web")
        return FileManager.default.fileExists(atPath: bundled.appendingPathComponent("index.html").path) ? bundled : nil
    }

    nonisolated static var dataDirectory: URL { DataHome.directory.appendingPathComponent("remote", isDirectory: true) }

    private func startGateway() {
        guard gateway == nil else { return }
        guard let executable = Self.gatewayExecutable else {
            state = .failed("The remote gateway is missing from this build")
            return
        }
        state = .starting
        var environment = ProcessInfo.processInfo.environment
        environment["VITALS_CHANNEL"] = Channel.current.rawValue
        environment["VITALS_REMOTE_DATA_DIR"] = Self.dataDirectory.path
        if let web = Self.webDirectory { environment["VITALS_REMOTE_WEB_DIR"] = web.path }
        gatewayGeneration += 1
        let generation = gatewayGeneration
        let process = GatewayProcess(
            executable: executable,
            environment: environment,
            onMessage: { [weak self] message in
                Task { @MainActor in self?.handle(message) }
            },
            onInvalid: { line in
                Log.notice(.remote, "gateway sent an unreadable line: \(line)")
            },
            onExit: { [weak self] code in
                Task { @MainActor in self?.gatewayExited(code, generation: generation) }
            }
        )
        do {
            try process.start()
            gateway = process
            startedAt = Date()
            updateVitalsNeeds()
            Log.notice(.remote, "gateway started (pid \(process.pid))")
        } catch {
            state = .failed(error.localizedDescription)
            Log.error(.remote, "gateway failed to start", error: error)
        }
    }

    private func stopGateway() {
        gatewayGeneration += 1
        restartTask?.cancel()
        restartTask = nil
        gateway?.stop()
        gateway = nil
        state = .off
        status = nil
        guardState = nil
        devices = []
        pairing = nil
        needs = .none
        updateVitalsNeeds()
        failAdminWaiters("Remote access is off")
    }

    private func gatewayExited(_ code: Int32, generation: Int) {
        guard generation == gatewayGeneration else { return }
        gateway = nil
        guardState = nil
        needs = .none
        updateVitalsNeeds()
        failAdminWaiters("The gateway stopped")
        guard settings.remoteEnabled else {
            state = .off
            return
        }
        if let startedAt, Date().timeIntervalSince(startedAt) > 30 { restartAttempt = 0 }
        restartAttempt += 1
        let delay = min(10, 0.5 * pow(2, Double(restartAttempt - 1)))
        state = .restarting(attempt: restartAttempt)
        Log.notice(.remote, "gateway exited (\(code)); restarting in \(delay)s")
        restartTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.startGateway()
        }
    }

    private func send(_ message: FromApp) {
        gateway?.send(message)
    }

    private func log(_ level: String, _ kind: String, _ data: [String: JSONValue]) {
        send(.log(level: level, kind: kind, data: data))
    }

    // MARK: Inbound

    private func handle(_ message: ToApp) {
        switch message {
        case .hello:
            state = .running
            lastGuardSent = nil
            send(.hello(mac: macInfo(), keepAwake: wireKeepAwake(keepAwake)))
            for alert in guardEngine.active { send(.event(.alertRaised(at: alert.raisedAt, alert: alert))) }
            Task { await refreshDevices() }
        case let .need(next):
            needs = next
            updateVitalsNeeds()
        case let .command(id, deviceId, deviceName, command):
            router.run(.init(id: id, deviceId: deviceId, deviceName: deviceName, command: command))
        case let .cancel(id):
            router.cancel(id)
        case let .query(id, query):
            Task { await answer(id, query) }
        case let .adminResult(id, result, error):
            guard let waiter = adminWaiters.removeValue(forKey: id) else { return }
            if let result { waiter.resume(returning: result) } else { waiter.resume(throwing: AdminFailure(message: error ?? "Failed")) }
        case let .status(next):
            status = next
            Task { await refreshDevices() }
        }
    }

    private func answer(_ id: String, _ query: BridgeQuery) async {
        switch query {
        case let .history(input):
            let series = await Task.detached(priority: .utility) {
                input.series.compactMap { name -> WireSeries? in
                    guard let buckets = HistoryDatabase.shared.buckets(series: name, from: input.from, to: input.to, points: input.points) else { return nil }
                    return WireSeries(name: name, buckets: buckets.map { WireBucket(t: $0.time, min: $0.min, avg: $0.avg, max: $0.max) })
                }
            }.value
            send(.result(id: id, ok: .history(series), error: nil))
        case .apps:
            let running = RunningApps.list()
            let emulators = await Task.detached(priority: .utility) { Emulators.list() }.value
            send(.result(id: id, ok: .apps(WireApps(running: running, emulators: emulators)), error: nil))
        case .clipboard:
            send(.result(id: id, ok: .clipboard(SystemControl.clipboard()), error: nil))
        case let .setGuard(next):
            applyGuardSettings(next)
            send(.result(id: id, ok: .setGuard(next), error: nil))
        }
    }

    // MARK: Admin (desktop only)

    func createPairing() async {
        adminError = nil
        do {
            if case let .createPairing(code, url, expiresAt) = try await admin(.createPairing) {
                pairing = Pairing(code: code, url: url, expiresAt: Date(timeIntervalSince1970: TimeInterval(expiresAt) / 1000))
            }
        } catch {
            adminError = (error as? AdminFailure)?.message ?? error.localizedDescription
        }
    }

    func clearPairing() { pairing = nil }

    func refreshDevices() async {
        guard let result = try? await admin(.listDevices), case let .listDevices(list) = result else { return }
        if pairing != nil, list.count > devices.count { pairing = nil }
        devices = list
    }

    func revoke(_ device: RemoteDevice) async {
        _ = try? await admin(.revokeDevice(device.id))
        await refreshDevices()
    }

    func setScope(_ scope: String, enabled: Bool, for device: RemoteDevice) async {
        guard let index = devices.firstIndex(where: { $0.id == device.id }) else { return }
        var scopes = Set(devices[index].scopes)
        if enabled { scopes.insert(scope) } else { scopes.remove(scope) }
        let next = Array(scopes).sorted()
        devices[index].scopes = next
        _ = try? await admin(.setScopes(deviceId: device.id, scopes: next))
        await refreshDevices()
    }

    private func admin(_ op: AdminOp) async throws -> AdminResult {
        guard gateway != nil else { throw AdminFailure(message: "Remote access is off") }
        let id = UUID().uuidString
        return try await withCheckedThrowingContinuation { continuation in
            adminWaiters[id] = continuation
            send(.admin(id: id, op: op))
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(10))
                self?.adminWaiters.removeValue(forKey: id)?.resume(throwing: AdminFailure(message: "The gateway did not answer"))
            }
        }
    }

    private func failAdminWaiters(_ message: String) {
        let waiters = adminWaiters
        adminWaiters.removeAll()
        waiters.values.forEach { $0.resume(throwing: AdminFailure(message: message)) }
    }

    // MARK: Sampling

    private func updateVitalsNeeds() {
        let active = gateway != nil
        vitals.setRemoteNeeds(
            topics: active ? Set(needs.topics) : [],
            processTable: active && (guardEngine.settings.enabled || needs.processes != nil)
        )
    }

    private func sampled(_ table: [ProcessSampler.Row]) {
        let now = Date()
        if gateway != nil, !needs.topics.isEmpty {
            sampleSeq += 1
            send(.sample(vitals.wireSample(seq: sampleSeq, topics: Set(needs.topics), at: now)))
        }
        let thermal = vitals.thermalState
        if thermal != lastThermal {
            lastThermal = thermal
            send(.event(.thermalChanged(at: Self.now(), state: thermal.wireName)))
        }
        guard gateway != nil, !table.isEmpty else { return }
        latestTable = table
        latestClassified = ProcessGroups.classify(table)
        if let request = needs.processes { send(.processes(processesSnapshot(limit: request.limit, at: now))) }
        evaluateGuard(now: now)
    }

    private func processesSnapshot(limit: Int, at date: Date) -> WireProcesses {
        let byCpu = latestTable.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(limit)
        let byMemory = latestTable.sorted { $0.memory > $1.memory }.prefix(limit)
        var seen = Set<pid_t>()
        let rows = (byCpu + byMemory)
            .filter { seen.insert($0.pid).inserted }
            .map { row -> WireProcessRow in
                let ref = ProcessRef(pid: row.pid, startTimeMs: row.startTimeMs)
                return WireProcessRow(
                    pid: row.pid,
                    startTimeMs: row.startTimeMs,
                    name: row.name,
                    group: latestClassified.group(of: row.pid).rawValue,
                    cpuPercent: row.cpuPercent,
                    memoryBytes: Double(row.memory),
                    throttled: throttled.contains(ref),
                    paused: paused.contains(ref)
                )
            }
        return WireProcesses(at: Int64(date.timeIntervalSince1970 * 1000), rows: Array(rows), groups: PressureGuard.wireTotals(latestClassified))
    }

    private func evaluateGuard(now: Date) {
        guard let memory = vitals.memory else { return }
        let changes = guardEngine.evaluate(.init(
            now: now,
            pressureLevel: memory.pressure.level,
            swapUsed: memory.swapUsed,
            cpuPercent: vitals.hasLoaded ? vitals.cpuUsage : nil,
            thermalLevel: vitals.thermalState.level,
            memoryTotal: memory.total,
            classified: latestClassified,
            table: latestTable
        ))
        for change in changes {
            switch change {
            case let .raised(alert):
                send(.event(.alertRaised(at: Self.now(), alert: alert)))
                NotificationManager.shared.send(
                    title: alert.severity == "critical" ? "Mac under heavy pressure" : "Mac under pressure",
                    body: "\(alert.summary). \(alert.plan.summary).",
                    id: "vitals.remote.alert.\(alert.id)",
                    categoryId: NotificationManager.Category.remotePressure
                )
            case let .cleared(alert):
                send(.event(.alertCleared(at: Self.now(), alert: alert)))
                NotificationManager.shared.remove(id: "vitals.remote.alert.\(alert.id)")
            }
        }
        let next = WireGuardState(
            settings: guardEngine.settings,
            pressure: memory.pressure.wireName,
            thermal: vitals.thermalState.wireName,
            swapUsedBytes: Double(memory.swapUsed),
            groups: PressureGuard.wireTotals(latestClassified),
            active: guardEngine.active,
            calmApplied: !calmActions.isEmpty
        )
        guardState = next
        if needs.guardState, next != lastGuardSent {
            lastGuardSent = next
            send(.guardState(next))
        }
    }

    // MARK: Commands

    private func configureRouter() {
        router.onReceipt = { [weak self] receipt in
            guard let self else { return }
            self.send(.receipt(receipt))
            if receipt.status != .pending { self.pendingCommands.removeValue(forKey: receipt.id) }
        }
        router.onGraceStarted = { [weak self] request, deadline in
            guard let self else { return }
            self.pendingCommands[request.id] = PendingCommand(deviceName: request.deviceName, kind: request.command.tag, deadline: deadline)
            NotificationManager.shared.send(
                title: "\(Self.label(request.command)) in \(request.command.graceSeconds) s",
                body: "Requested from \(request.deviceName). Cancel to keep working.",
                id: request.id,
                categoryId: NotificationManager.Category.remoteGrace
            )
        }
        router.onGraceEnded = { id in NotificationManager.shared.remove(id: id) }
        router.onWillPowerOff = { [weak self] in self?.send(.event(.willPowerOff(at: Self.now()))) }
    }

    func cancelPending(_ id: String) { router.cancel(id) }

    func applyGuardSettings(_ next: GuardSettings) {
        settings.guardSettings = next
        guardEngine.settings = next
        updateVitalsNeeds()
    }

    private func handleNotificationAction(_ action: NotificationManager.RemoteAction) {
        switch action {
        case let .cancelCommand(id): router.cancel(id)
        case .calmDown: _ = calmDown()
        }
    }

    func execute(_ command: RemoteCommand) async -> String? {
        switch command {
        case let .keepAwake(until, display, whileProcess):
            return power.startKeepAwake(
                until: until.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) },
                display: display,
                whileProcess: whileProcess
            )
        case .allowSleep:
            power.stopKeepAwake()
            return nil
        case let .processes(actions):
            return apply(actions)
        case .calmDown:
            return calmDown()
        case .undoCalm:
            return undoCalm()
        case .locate:
            SystemControl.locate()
            NotificationManager.shared.send(title: "Here I am", body: "Vitals Remote asked this Mac to identify itself.", id: "vitals.remote.locate")
            return nil
        default:
            return await SystemCommandExecutor.perform(command)
        }
    }

    private func apply(_ actions: [ProcessAction]) -> String? {
        var failures: [String] = []
        for action in actions {
            if let failure = ProcessControl.apply(action, isProtected: { pid in
                self.latestClassified.groupByPid[pid].map { $0 == .protected } ?? ProcessGroups.isProtectedNow(pid)
            }) {
                failures.append("\(action.target.pid): \(failure.message)")
                continue
            }
            switch action.action {
            case .throttle: throttled.insert(action.target)
            case .unthrottle: throttled.remove(action.target)
            case .pause: paused.insert(action.target)
            case .resume: paused.remove(action.target)
            case .terminate, .kill:
                throttled.remove(action.target)
                paused.remove(action.target)
            }
        }
        return failures.isEmpty ? nil : failures.prefix(5).joined(separator: "; ")
    }

    @discardableResult
    func calmDown() -> String? {
        let plan = PressureGuard.calmPlan(latestTable, classified: latestClassified)
        guard !plan.actions.isEmpty else { return "Nothing to calm right now" }
        let error = apply(plan.actions)
        calmActions += plan.actions
        log("info", "guard.calm.applied", ["actions": .number(Double(plan.actions.count))])
        return error
    }

    @discardableResult
    func undoCalm() -> String? {
        let reversed = calmActions.compactMap { action -> ProcessAction? in
            switch action.action {
            case .throttle: return ProcessAction(target: action.target, action: .unthrottle)
            case .pause: return ProcessAction(target: action.target, action: .resume)
            default: return nil
            }
        }
        calmActions.removeAll()
        guard !reversed.isEmpty else { return nil }
        _ = apply(reversed)
        log("info", "guard.calm.undone", ["actions": .number(Double(reversed.count))])
        return nil
    }

    func toggleKeepAwake() {
        if keepAwake.active { power.stopKeepAwake() } else { _ = power.startKeepAwake(until: nil, display: false, whileProcess: nil) }
    }

    private func keepAwakeChanged(_ state: PowerControl.KeepAwake) {
        keepAwake = state
        send(.event(.keepAwakeChanged(at: Self.now(), state: wireKeepAwake(state))))
    }

    // MARK: Helpers

    private func wireKeepAwake(_ state: PowerControl.KeepAwake) -> WireKeepAwake {
        WireKeepAwake(
            active: state.active,
            display: state.display,
            until: state.until.map { Int64($0.timeIntervalSince1970 * 1000) },
            whileProcess: state.whileProcess
        )
    }

    private func macInfo() -> WireMac {
        WireMac(
            name: Host.current().localizedName ?? "Mac",
            model: HardwareInfo.modelIdentifier,
            chip: HardwareInfo.chipName,
            os: HardwareInfo.osVersion,
            coreCount: HardwareInfo.coreCount,
            memoryBytes: Double(ProcessInfo.processInfo.physicalMemory),
            hasBattery: vitals.battery != nil,
            hasFans: !vitals.fans.isEmpty,
            vitalsVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev",
            channel: Channel.current.rawValue
        )
    }

    static func label(_ command: RemoteCommand) -> String {
        switch command {
        case .sleep: return "Sleep"
        case .restart: return "Restart"
        case .shutDown: return "Shut down"
        case .logOut: return "Log out"
        default: return command.tag
        }
    }

    static func now() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
}

@MainActor
final class SystemCommandExecutor: CommandExecutor {
    private weak var model: RemoteModel?

    init(model: RemoteModel) { self.model = model }

    func execute(_ command: RemoteCommand) async -> String? {
        guard let model else { return "Vitals is shutting down" }
        return await model.execute(command)
    }

    static func perform(_ command: RemoteCommand) async -> String? {
        switch command {
        case .displayOff: return SystemPower.displaySleep()
        case .lock: return SystemPower.lock()
        case .sleep: return SystemPower.send(.sleep)
        case .restart: return SystemPower.send(.restart)
        case .shutDown: return SystemPower.send(.shutDown)
        case .logOut: return SystemPower.send(.logOut)
        case let .quitApp(app): return RunningApps.quit(app)
        case let .hideApp(app): return RunningApps.hide(app)
        case let .forceQuitApp(app): return RunningApps.forceQuit(app)
        case let .launchApp(bundleId): return await RunningApps.launch(bundleId: bundleId)
        case let .stopEmulator(kind, id): return await Task.detached { Emulators.stop(kind: kind, id: id) }.value
        case let .setVolume(level): return SystemControl.setVolume(level)
        case let .setMuted(muted): return SystemControl.setMuted(muted)
        case let .clipboardSet(text): return SystemControl.setClipboard(text)
        case let .openURL(url): return SystemControl.open(url)
        case .keepAwake, .allowSleep, .processes, .calmDown, .undoCalm, .locate:
            return "Handled by the remote model"
        }
    }
}
