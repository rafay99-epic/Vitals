import Foundation
import AppKit
import SystemConfiguration

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
    /// Phones on the Wi-Fi waiting for Allow or Deny, oldest first.
    private(set) var pairPrompts: [PairPrompt] = []
    /// What the gateway's clip history holds. nil until it reports.
    private(set) var clipStats: ClipStats?
    /// macOS denies Vitals pasteboard reads (Privacy & Security > Paste from Other Apps).
    private(set) var clipReadsBlocked = false
    let lanAdvertiser = LanAdvertiser()
    let share: ShareModel

    var isEnabled: Bool { settings.remoteEnabled }
    var clipHistoryEnabled: Bool { settings.clipHistoryEnabled }
    var browseEverything: Bool { settings.browseEverything }
    private(set) var terminals: [MacTerminal] = []
    @ObservationIgnored private var announcedTerminals = Set<String>()
    var clipKeepDays: Int { settings.clipKeepDays }

    @ObservationIgnored private let vitals: VitalsModel
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let power = PowerControl()
    @ObservationIgnored private lazy var router = CommandRouter(executor: SystemCommandExecutor(model: self))
    @ObservationIgnored private lazy var clipWatcher: ClipWatcher = {
        let watcher = ClipWatcher(directory: Self.clipsDirectory)
        watcher.onClips = { [weak self] clips in clips.forEach { self?.send(.clip($0)) } }
        return watcher
    }()
    @ObservationIgnored private var gateway: GatewayProcess?
    @ObservationIgnored private var restartTask: Task<Void, Never>?
    @ObservationIgnored private var restartAttempt = 0
    @ObservationIgnored private var gatewayGeneration = 0
    @ObservationIgnored private var startedAt: Date?
    @ObservationIgnored private var needs = NeedsMessage.none
    @ObservationIgnored private var classifyGeneration = 0
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
    @ObservationIgnored private var promptExpiry: [String: Task<Void, Never>] = [:]

    struct AdminFailure: Error, Equatable { let message: String }

    init(vitals: VitalsModel, settings: AppSettings) {
        self.vitals = vitals
        self.settings = settings
        share = ShareModel(settings: settings)
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
        share.remote = self
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
    /// Clip bytes shared with the gateway, which serves and prunes them.
    nonisolated static var clipsDirectory: URL { dataDirectory.appendingPathComponent("clips", isDirectory: true) }

    private func startGateway() {
        guard gateway == nil else { return }
        guard let executable = Self.gatewayExecutable else {
            state = .failed("The remote gateway is missing from this build")
            return
        }
        state = .starting
        NotificationManager.shared.requestAuthorizationIfNeeded()
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
        clipStats = nil
        updateClipWatcher()
        share.disconnected()
        devices = []
        pairing = nil
        needs = .none
        lanAdvertiser.update(nil)
        endAllPairPrompts()
        updateVitalsNeeds()
        failAdminWaiters("Remote access is off")
    }

    private func gatewayExited(_ code: Int32, generation: Int) {
        guard generation == gatewayGeneration else { return }
        gateway = nil
        guardState = nil
        needs = .none
        updateClipWatcher()
        share.disconnected()
        lanAdvertiser.update(nil)
        endAllPairPrompts()
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

    func bridge(_ message: FromApp) -> Bool {
        guard gateway != nil, state == .running else { return false }
        send(message)
        return true
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
            sendClipPolicy()
            sendFsPolicy()
            share.connected()
            updateClipWatcher()
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
            lanAdvertiser.update(next.lan)
            Task { await refreshDevices() }
        case let .pairPrompt(prompt):
            showPairPrompt(prompt)
        case let .pairPromptEnded(id):
            endPairPrompt(id)
            Task { await refreshDevices() }
        case let .clipStats(stats):
            clipStats = stats
        case let .drop(drop):
            share.update(drop)
        case let .dropRemoved(id):
            share.remove(id)
        case let .dropReceived(id, from, files, dest):
            share.receivedFiles(id: id, from: from, files: files, dest: dest)
        case let .terminals(sessions):
            updateTerminals(sessions)
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
        case let .clipMaterialize(clipID, kind, origin):
            let directory = Self.clipsDirectory
            let result = await Task.detached(priority: .userInitiated) {
                Result { try ClipDrop.materialize(id: clipID, kind: kind, origin: origin, into: directory) }
            }.value
            switch result {
            case let .success(made):
                send(.result(id: id, ok: .clipMaterialize(stored: made.stored, bytes: made.bytes, files: made.files), error: nil))
            case let .failure(error):
                send(.result(id: id, ok: nil, error: Self.clipMessage(error)))
            }
        case let .clipPut(items, to, folder, deviceName):
            do {
                let placed = try await placeClips(items, to: to, folder: folder, deviceName: deviceName)
                send(.result(id: id, ok: .clipPut(placed: placed), error: nil))
            } catch {
                send(.result(id: id, ok: nil, error: Self.clipMessage(error)))
            }
        case let .fsThumbs(paths, pixels):
            let thumbs = await FileThumbs.make(paths: paths, pixels: pixels)
            send(.result(id: id, ok: .fsThumbs(thumbs), error: nil))
        case let .fsTrash(paths, deviceName):
            let trashed = await Task.detached(priority: .userInitiated) { FileThumbs.trash(paths) }.value
            send(.result(id: id, ok: .fsTrash(trashed: trashed), error: nil))
            if trashed > 0 {
                share.note("\(deviceName) moved \(trashed == 1 ? "1 item" : "\(trashed) items") to the Trash", "Put it back from the Trash in Finder.")
            }
        case let .fsOpen(path):
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
            send(.result(id: id, ok: .fsOpen, error: nil))
        }
    }

    // MARK: Clipboard history and drop

    func setBrowseEverything(_ enabled: Bool) {
        guard settings.browseEverything != enabled else { return }
        settings.browseEverything = enabled
        sendFsPolicy()
    }

    private func sendFsPolicy() {
        send(.fsPolicy(access: settings.browseEverything ? "everything" : "folders"))
    }

    func setClipHistory(enabled: Bool) {
        guard settings.clipHistoryEnabled != enabled else { return }
        settings.clipHistoryEnabled = enabled
        sendClipPolicy()
        updateClipWatcher()
    }

    func setClipKeepDays(_ days: Int) {
        guard settings.clipKeepDays != days else { return }
        settings.clipKeepDays = days
        sendClipPolicy()
    }

    /// Deletes unpinned history on the gateway; it answers with fresh `clipStats`.
    func clearClipHistory() { send(.clipClear) }

    func refreshClipAccess() { clipReadsBlocked = ClipWatcher.readsBlocked }

    func pushClipboard() async -> MacClip? {
        let clips = await clipWatcher.push()
        guard gateway != nil, state == .running else { return nil }
        clips.forEach { send(.clip($0)) }
        return clips.first
    }

    func writeClipboard(_ entries: [ClipDrop.Entry]) -> Int? {
        guard ClipDrop.write(entries) else { return nil }
        clipWatcher.noteOwnWrite()
        return NSPasteboard.general.changeCount
    }

    private func sendClipPolicy() {
        send(.clipPolicy(ClipPolicy(enabled: settings.clipHistoryEnabled, keepDays: min(90, max(1, settings.clipKeepDays)))))
    }

    /// The pasteboard poll runs only while the gateway is up and history is on; otherwise no timer exists.
    private func updateClipWatcher() {
        if gateway != nil, state == .running, settings.clipHistoryEnabled {
            clipWatcher.start()
            refreshClipAccess()
        } else {
            clipWatcher.stop()
        }
    }

    private func placeClips(_ items: [ClipPlacement], to destination: ClipDestination, folder: String?, deviceName: String) async throws -> Int {
        guard !items.isEmpty else { return 0 }
        let directory = Self.clipsDirectory
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        switch destination {
        case .downloads:
            _ = try await Task.detached(priority: .userInitiated) {
                try ClipDrop.save(try ClipDrop.resolve(items, in: directory), to: downloads, folder: folder, deviceName: deviceName)
            }.value
        case .clipboard:
            let (sources, entries) = try await Task.detached(priority: .userInitiated) {
                let sources = try ClipDrop.resolve(items, in: directory)
                return (sources, try ClipDrop.clipboardEntries(sources, downloads: downloads, deviceName: deviceName))
            }.value
            guard let count = writeClipboard(entries) else { throw ClipDrop.Failure("Clipboard write failed") }
            share.phoneCopied(device: deviceName, sources: sources, entries: entries, changeCount: count)
        }
        let summary = ClipDrop.summary(items.map(\.kind), to: destination, folder: folder, deviceName: deviceName)
        NotificationManager.shared.send(title: summary.title, body: summary.body, id: "vitals.remote.clip.\(UUID().uuidString)", quiet: share.panelOpen)
        return items.count
    }

    private static func clipMessage(_ error: Error) -> String {
        (error as? ClipDrop.Failure)?.message ?? error.localizedDescription
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

    private func updateTerminals(_ sessions: [MacTerminal]) {
        let known = Set(terminals.map(\.id))
        for session in sessions where !known.contains(session.id) && !announcedTerminals.contains(session.id) {
            announcedTerminals.insert(session.id)
            NotificationManager.shared.send(
                title: "\(session.deviceName) opened a terminal",
                body: "It runs commands on this Mac as you. End it in Vitals › Remote.",
                id: "vitals.terminal.\(session.id)"
            )
        }
        terminals = sessions
    }

    func phoneDevices() async -> [PhoneDevice] {
        guard case let .fsDevices(devices)? = try? await admin(.fsDevices) else { return [] }
        return devices
    }

    func phoneRoots(_ device: String) async throws -> [PhoneRoot] {
        guard case let .fsRoots(roots) = try await admin(.fsRoots(device: device)) else { return [] }
        return roots
    }

    func phoneList(_ device: String, path: String) async throws -> PhoneListing? {
        guard case let .fsList(listing) = try await admin(.fsList(device: device, path: path, offset: 0)) else { return nil }
        return listing
    }

    func pullFromPhone(_ device: String, paths: [String]) async throws -> Int {
        guard case let .fsPull(files) = try await admin(.fsPull(device: device, paths: paths)) else { return 0 }
        return files
    }

    func endTerminal(_ id: String) {
        send(.terminalEnd(id: id, deviceId: nil))
    }

    func endAllTerminals() {
        send(.terminalEnd(id: nil, deviceId: nil))
    }

    func setScope(_ scope: String, enabled: Bool, for device: RemoteDevice) async {
        if scope == "terminal", !enabled { send(.terminalEnd(id: nil, deviceId: device.id)) }
        guard let index = devices.firstIndex(where: { $0.id == device.id }) else { return }
        var scopes = Set(devices[index].scopes)
        if enabled { scopes.insert(scope) } else { scopes.remove(scope) }
        let next = Array(scopes).sorted()
        devices[index].scopes = next
        _ = try? await admin(.setScopes(deviceId: device.id, scopes: next))
        await refreshDevices()
    }

    // MARK: Wi-Fi pairing

    /// Notification first; RemoteView lists the same prompts for when notifications are off.
    private func showPairPrompt(_ prompt: PairPrompt) {
        pairPrompts.removeAll { $0.id == prompt.id }
        pairPrompts.append(prompt)
        NotificationManager.shared.send(
            title: "\(prompt.device.name) wants to connect",
            body: "over Wi-Fi · code \(prompt.code) · watch, control, send and browse files",
            id: NotificationManager.pairNotificationId(prompt.id),
            categoryId: NotificationManager.Category.remotePair
        )
        promptExpiry[prompt.id]?.cancel()
        promptExpiry[prompt.id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, prompt.expiry.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            self?.endPairPrompt(prompt.id)
        }
    }

    private func endPairPrompt(_ id: String) {
        pairPrompts.removeAll { $0.id == id }
        promptExpiry.removeValue(forKey: id)?.cancel()
        NotificationManager.shared.remove(id: NotificationManager.pairNotificationId(id))
    }

    private func endAllPairPrompts() {
        pairPrompts.map(\.id).forEach(endPairPrompt)
    }

    func resolvePairPrompt(_ id: String, allow: Bool) async {
        endPairPrompt(id)
        do {
            _ = try await admin(.resolvePairPrompt(id: id, allow: allow))
        } catch {
            Log.notice(.remote, "couldn't resolve pair prompt \(id)", error: error)
        }
        if allow { await refreshDevices() }
    }

    private func admin(_ op: AdminOp) async throws -> AdminResult {
        guard gateway != nil else { throw AdminFailure(message: "Remote access is off") }
        let id = UUID().uuidString
        return try await withCheckedThrowingContinuation { continuation in
            adminWaiters[id] = continuation
            send(.admin(id: id, op: op))
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(20))
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
        vitals.setRemoteNeeds(topics: gateway == nil ? [] : Set(needs.topics), processTable: processTableDemand)
    }

    private var processTableDemand: VitalsModel.ProcessTableDemand {
        guard gateway != nil else { return .off }
        if needs.processes != nil { return .live }
        return guardEngine.settings.enabled ? .guardOnly : .off
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
        guard gateway != nil else { return }
        if !table.isEmpty { classify(table) }
        if processTableDemand != .off, !latestTable.isEmpty { evaluateGuard(now: now) }
    }

    /// Grouping walks every process's parent chain, so it runs off the main actor.
    /// A newer table supersedes a slower, older result; the table and its
    /// classification are always swapped in together.
    private func classify(_ table: [ProcessSampler.Row]) {
        classifyGeneration += 1
        let generation = classifyGeneration
        Task { [weak self] in
            let classified = await Task.detached(priority: .utility) { ProcessGroups.classify(table) }.value
            guard let self, generation == self.classifyGeneration, self.gateway != nil else { return }
            self.latestTable = table
            self.latestClassified = classified
            if let request = self.needs.processes { self.send(.processes(self.processesSnapshot(limit: request.limit, at: Date()))) }
        }
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
        if next != guardState { guardState = next }
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
        case let .resolvePair(id, allow): Task { await resolvePairPrompt(id, allow: allow) }
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
        case let .clipboardSet(text):
            let error = SystemControl.setClipboard(text)
            clipWatcher.noteOwnWrite()
            return error
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
            name: SCDynamicStoreCopyComputerName(nil, nil) as String? ?? "Mac",
            model: HardwareInfo.modelIdentifier,
            chip: HardwareInfo.chipName,
            os: HardwareInfo.osVersion,
            coreCount: HardwareInfo.coreCount,
            memoryBytes: Double(ProcessInfo.processInfo.physicalMemory),
            hasBattery: vitals.battery != nil || Battery.isPresent,
            hasFans: !vitals.fans.isEmpty || (SMC()?.fanCount ?? 0) > 0,
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
