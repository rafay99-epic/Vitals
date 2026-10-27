import AppKit
import Foundation

@MainActor
@Observable
final class ShareModel {
    enum Origin: Equatable { case menuBar, dock, finder, sheet }

    struct Batch: Identifiable, Equatable {
        let id = UUID()
        let items: [DropFiles.Item]

        var files: [MacDropFile] { items.flatMap(\.files) }
        var bytes: Int { items.reduce(0) { $0 + $1.bytes } }
        var label: String { items.count == 1 ? items[0].name : "\(items.count) items" }

        var summary: String {
            let count = files.count
            return [label, count > 1 ? ShareFormat.files(count) : nil, ShareFormat.size(bytes)].compactMap { $0 }.joined(separator: " · ")
        }
    }

    struct Draft: Identifiable, Equatable {
        let id = UUID()
        var items: [DropFiles.Item]
        var to: Set<String>
        var adding = 0
        var error: String?
    }

    struct PhoneCopy: Equatable {
        let device: String
        let preview: String
        let entries: [ClipDrop.Entry]
        let at: Date
        var changeCount: Int
    }

    struct ClipSent: Equatable {
        let to: String
        let at: Date
    }

    private(set) var drops: [Drop] = []
    private(set) var percent: Int?
    private(set) var phoneCopy: PhoneCopy?
    private(set) var clipSent: ClipSent?
    private(set) var received: [String: DropFiles.Placed] = [:]
    private(set) var sent: [String: [MacDropFile]] = [:]
    private(set) var hotKeyFailed = false
    var draft: Draft?
    var recordingShortcut = false { didSet { registerHotKey() } }

    @ObservationIgnored weak var remote: RemoteModel?
    @ObservationIgnored var panelOpen = false
    @ObservationIgnored var presentPicker: ((Batch) -> Bool)?
    @ObservationIgnored var presentPanel: (() -> Void)?
    @ObservationIgnored var openSharing: (() -> Void)?
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let hotKey = HotKey()
    @ObservationIgnored private var known: [String: Drop] = [:]
    @ObservationIgnored private var pending: [String: Drop] = [:]
    @ObservationIgnored private var flushTask: Task<Void, Never>?
    @ObservationIgnored private var unmatched: [(deviceId: String, files: [MacDropFile])] = []
    @ObservationIgnored private var deferred: [(urls: [URL], origin: Origin)] = []

    static let freshness: TimeInterval = 600
    static let flushDelay: Duration = .milliseconds(250)
    static let maxLineBytes = 1_000_000
    static let largestOptions = [10, 50, 200]

    init(settings: AppSettings) {
        self.settings = settings
        hotKey.onPress = { [weak self] in self?.sendClipboard() }
        NotificationManager.shared.onShareAction = { [weak self] action in self?.handle(action) }
        observeChanges(of: { settings.remoteEnabled }, { [weak self] _ in self?.registerHotKey() })
        registerHotKey()
    }

    // MARK: Settings

    nonisolated static var defaultFolder: URL {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        return downloads.appendingPathComponent("Vitals", isDirectory: true)
    }

    static func policy(_ settings: AppSettings) -> DropPolicy {
        DropPolicy(autoAccept: settings.shareAutoAccept, askWeb: settings.shareAskWeb, maxBytes: max(1, settings.shareMaxGB) * 1_000_000_000)
    }

    var folder: URL {
        settings.shareFolder.isEmpty ? Self.defaultFolder : URL(fileURLWithPath: settings.shareFolder, isDirectory: true)
    }

    func setFolder(_ url: URL) {
        settings.shareFolder = url.standardizedFileURL == Self.defaultFolder.standardizedFileURL ? "" : url.path
    }

    var autoAccept: Bool {
        get { settings.shareAutoAccept }
        set { settings.shareAutoAccept = newValue; sendPolicy() }
    }

    var askWeb: Bool {
        get { settings.shareAskWeb }
        set { settings.shareAskWeb = newValue; sendPolicy() }
    }

    var largestGB: Int {
        get { settings.shareMaxGB }
        set { settings.shareMaxGB = newValue; sendPolicy() }
    }

    var shortcut: Shortcut? { settings.clipShortcut }

    func setShortcut(_ shortcut: Shortcut?) {
        settings.clipShortcut = shortcut
        recordingShortcut = false
    }

    private func registerHotKey() {
        let wanted = settings.remoteEnabled && !recordingShortcut ? settings.clipShortcut : nil
        let failed = !hotKey.register(wanted)
        if failed != hotKeyFailed { hotKeyFailed = failed }
    }

    func sendPolicy() {
        _ = remote?.bridge(.dropPolicy(Self.policy(settings)))
    }

    // MARK: Phones

    var phones: [RemoteDevice] {
        (remote?.devices ?? []).filter { $0.revokedAt == nil && $0.platform != "web" && $0.scopes.contains("files") }
    }

    var clipPhones: [RemoteDevice] {
        (remote?.devices ?? []).filter { $0.revokedAt == nil && $0.scopes.contains("clipboard") }
    }

    var lastPhone: String { settings.shareLastPhone }

    var defaultTargets: Set<String> {
        let phones = phones
        if phones.contains(where: { $0.id == lastPhone }) { return [lastPhone] }
        return phones.first.map { [$0.id] } ?? []
    }

    // MARK: Bridge

    func connected() {
        sendPolicy()
        guard !deferred.isEmpty else { return }
        let queued = deferred
        deferred = []
        Task { [weak self] in
            await self?.remote?.refreshDevices()
            for entry in queued { self?.offer(entry.urls, from: entry.origin) }
        }
    }

    private var gatewayComing: Bool {
        switch remote?.state {
        case .starting, .restarting: return true
        default: return false
        }
    }

    func disconnected() {
        flushTask?.cancel()
        flushTask = nil
        pending = [:]
        for drop in known.values { clearNotes(drop) }
        known = [:]
        unmatched = []
        publish()
    }

    func update(_ drop: Drop) {
        if let old = known[drop.id], old.state == drop.state {
            pending[drop.id] = drop
            scheduleFlush()
        } else {
            pending.removeValue(forKey: drop.id)
            commit([drop])
        }
    }

    func remove(_ id: String) {
        pending.removeValue(forKey: id)
        guard let old = known.removeValue(forKey: id) else { return }
        clearNotes(old)
        publish()
    }

    private func scheduleFlush() {
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: Self.flushDelay)
            guard !Task.isCancelled, let self else { return }
            self.flushTask = nil
            let batch = Array(self.pending.values)
            self.pending = [:]
            self.commit(batch)
        }
    }

    private func commit(_ batch: [Drop]) {
        for drop in batch {
            let old = known[drop.id]
            known[drop.id] = drop
            if old == nil, drop.isOutgoing { adopt(drop) }
            transition(from: old, to: drop)
        }
        publish()
    }

    private func publish() {
        let next = known.values.sorted { $0.createdAt == $1.createdAt ? $0.id > $1.id : $0.createdAt > $1.createdAt }
        if next != drops { drops = next }
        let active = next.filter(\.state.isActive)
        let total = active.reduce(0) { $0 + $1.bytes }
        let done = active.reduce(0) { $0 + $1.done }
        let value: Int? = active.contains { $0.state == .running } ? (total > 0 ? min(100, done * 100 / total) : 0) : nil
        if value != percent { percent = value }
    }

    private static func signature(_ files: [(String, Int)]) -> [String] {
        files.map { "\($0.0)\u{0}\($0.1)" }.sorted()
    }

    private func adopt(_ drop: Drop) {
        guard let deviceId = drop.to.deviceId else { return }
        let signature = Self.signature(drop.files.map { ($0.path ?? $0.name, $0.size) })
        guard let index = unmatched.firstIndex(where: {
            $0.deviceId == deviceId && Self.signature($0.files.map { ($0.path ?? $0.name, $0.size) }) == signature
        }) else { return }
        sent[drop.id] = unmatched.remove(at: index).files
    }

    private func transition(from old: Drop?, to drop: Drop) {
        guard old?.state != drop.state else { return }
        if let old { clearNotes(old) }
        let phone = drop.phone.name
        switch drop.state {
        case .asking where !drop.isOutgoing:
            let what = drop.files.count == 1 ? drop.files[0].name : ShareFormat.files(drop.files.count)
            note(
                "\(phone) wants to send \(what) (\(ShareFormat.size(drop.bytes)))",
                drop.files.prefix(5).map(\.name).joined(separator: ", "),
                id: NotificationManager.shareNotificationId(NotificationManager.Category.shareAsk, drop.id),
                category: NotificationManager.Category.shareAsk
            )
        case .waiting where drop.isOutgoing:
            note(
                "Waiting for \(phone)",
                "Open Vitals on the phone. \(Self.label(drop)) sends when it connects.",
                id: NotificationManager.shareNotificationId(NotificationManager.Category.shareWait, drop.id),
                category: NotificationManager.Category.shareWait
            )
        case .done where drop.isOutgoing && old != nil:
            let over = drop.route.map { " over \($0.label)" } ?? ""
            note("Sent \(Self.label(drop)) to \(phone)", "\(ShareFormat.size(drop.bytes))\(over)", id: "vitals.share.sent.\(drop.id)")
        default:
            break
        }
    }

    private func clearNotes(_ drop: Drop) {
        if drop.state == .asking {
            NotificationManager.shared.remove(id: NotificationManager.shareNotificationId(NotificationManager.Category.shareAsk, drop.id))
        }
        if drop.state == .waiting {
            NotificationManager.shared.remove(id: NotificationManager.shareNotificationId(NotificationManager.Category.shareWait, drop.id))
        }
    }

    static func label(_ drop: Drop) -> String {
        DropFiles.label(DropFiles.topLevelNames(drop.files.map { ($0.name, $0.path) }))
    }

    // MARK: Actions

    func decide(_ id: String, accept: Bool) {
        NotificationManager.shared.remove(id: NotificationManager.shareNotificationId(NotificationManager.Category.shareAsk, id))
        _ = remote?.bridge(.dropDecision(id: id, accept: accept))
    }

    func cancel(_ id: String) {
        NotificationManager.shared.remove(id: NotificationManager.shareNotificationId(NotificationManager.Category.shareWait, id))
        _ = remote?.bridge(.dropCancel(id: id))
    }

    func setPaused(_ id: String, _ paused: Bool) {
        _ = remote?.bridge(.dropPause(id: id, paused: paused))
    }

    func canRetry(_ drop: Drop) -> Bool {
        drop.isOutgoing && (drop.state == .failed || drop.state == .cancelled) && sent[drop.id] != nil
    }

    func retry(_ drop: Drop) {
        guard let files = sent[drop.id], let to = drop.to.deviceId else { return }
        send(files, to: [to])
    }

    func reveal(_ id: String) {
        let items = (received[id]?.items ?? []).filter { FileManager.default.fileExists(atPath: $0.path) }
        if items.isEmpty {
            NSWorkspace.shared.open(folder)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting(items)
        }
    }

    private func handle(_ action: NotificationManager.ShareAction) {
        switch action {
        case let .show(id): reveal(id)
        case let .decide(id, accept): decide(id, accept: accept)
        case let .cancel(id): cancel(id)
        }
    }

    // MARK: Receiving

    func receivedFiles(id: String, from: DropPeer, files: [ReceivedDropFile], dest: String?) {
        let staging = RemoteModel.dataDirectory.appendingPathComponent("drop", isDirectory: true)
        let folder = dest.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? folder
        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                Result { try DropFiles.place(files, staging: staging, into: folder) }
            }.value
            guard let self else { return }
            switch result {
            case let .success(placed):
                guard placed.files > 0 else {
                    if placed.failed > 0 { self.note("Couldn't save files from \(from.name)", "They're no longer waiting on this Mac.") }
                    return
                }
                self.received[id] = placed
                let what = placed.items.count == 1 && placed.files == 1 ? placed.items[0].lastPathComponent : ShareFormat.files(placed.files)
                let failed = placed.failed > 0 ? " · \(placed.failed) couldn't be saved" : ""
                self.note(
                    "Got \(what) from \(from.name)",
                    "In \(ShareFormat.folder(folder)) · \(ShareFormat.size(placed.bytes))\(failed)",
                    id: NotificationManager.shareNotificationId(NotificationManager.Category.shareGot, id),
                    category: NotificationManager.Category.shareGot
                )
            case let .failure(error):
                self.note("Couldn't save files from \(from.name)", (error as? DropFiles.Failure)?.message ?? error.localizedDescription)
            }
        }
    }

    // MARK: Sending

    func offer(_ urls: [URL], from origin: Origin) {
        guard !urls.isEmpty else { return }
        guard remote?.state == .running else {
            if gatewayComing {
                deferred.append((urls: urls, origin: origin))
            } else {
                note("Remote access is off", "Turn it on in Remote to send files to your phone.")
            }
            return
        }
        guard !phones.isEmpty else {
            note("No phone can get files", "Turn on Files for a phone in Remote › Devices.")
            return
        }
        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) { Result { try DropFiles.expand(urls) } }.value
            guard let self else { return }
            switch result {
            case let .success(items): self.route(Batch(items: items), from: origin)
            case let .failure(error): self.note("Couldn't send", (error as? DropFiles.Failure)?.message ?? error.localizedDescription)
            }
        }
    }

    private func route(_ batch: Batch, from origin: Origin) {
        let phones = phones
        if phones.count == 1 {
            if send(batch.files, to: [phones[0].id]) { opened(origin) }
            return
        }
        if origin != .dock, presentPicker?(batch) == true { return }
        draft = Draft(items: batch.items, to: defaultTargets)
        openSharing?()
    }

    func pick(_ batch: Batch, to ids: [String], from origin: Origin) {
        if send(batch.files, to: ids) { opened(origin) }
    }

    private func opened(_ origin: Origin) {
        switch origin {
        case .menuBar: presentPanel?()
        case .dock: openSharing?()
        case .finder, .sheet: break
        }
    }

    func openDraft() {
        draft = Draft(items: [], to: defaultTargets)
    }

    func addToDraft(_ urls: [URL]) {
        let fresh = urls.filter { url in draft?.items.contains { $0.url == url } == false }
        guard !fresh.isEmpty, draft != nil else { return }
        draft?.adding += 1
        draft?.error = nil
        let id = draft?.id
        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) { Result { try DropFiles.expand(fresh) } }.value
            guard let self, self.draft?.id == id else { return }
            self.draft?.adding -= 1
            switch result {
            case let .success(items): self.draft?.items += items
            case let .failure(error): self.draft?.error = (error as? DropFiles.Failure)?.message ?? error.localizedDescription
            }
        }
    }

    func sendDraft() {
        guard let draft else { return }
        let ids = phones.map(\.id).filter(draft.to.contains)
        if send(Batch(items: draft.items).files, to: ids) { self.draft = nil }
    }

    @discardableResult
    func send(_ files: [MacDropFile], to ids: [String]) -> Bool {
        let to = Array(ids.prefix(8))
        guard !files.isEmpty, !to.isEmpty else { return false }
        guard files.count <= DropFiles.maxFiles else {
            note("Too many files at once", DropFiles.tooMany.message)
            return false
        }
        let message = FromApp.dropSend(to: to, files: files)
        guard let encoded = try? JSONEncoder().encode(message), encoded.count <= Self.maxLineBytes else {
            note("Too many files at once", "Send fewer files, or zip the folder first.")
            return false
        }
        guard remote?.bridge(message) == true else {
            note("Remote access is off", "Turn it on in Remote to send files to your phone.")
            return false
        }
        unmatched += to.map { (deviceId: $0, files: files) }
        if to.count == 1, settings.shareLastPhone != to[0] { settings.shareLastPhone = to[0] }
        return true
    }

    // MARK: Clipboard

    func sendClipboard() {
        guard let remote, remote.state == .running else {
            note("Remote access is off", "Turn it on in Remote to send your clipboard.")
            return
        }
        let targets = clipPhones
        guard !targets.isEmpty else {
            note("No phone can get your clipboard", "Turn on Read clipboard for a phone in Remote › Devices.")
            return
        }
        Task { [weak self] in
            let clip = await remote.pushClipboard()
            guard let self else { return }
            guard let clip else {
                self.note("Nothing to send", "The clipboard is empty, or holds something private.")
                return
            }
            let to = targets.count > 3 ? "your phones" : ShareFormat.names(targets.map(\.name))
            self.clipSent = ClipSent(to: to, at: Date())
            self.note("Sent your clipboard to \(to)", Self.preview(clip), id: "vitals.share.clip")
        }
    }

    static func preview(_ clip: MacClip) -> String {
        switch clip.kind {
        case .text, .link: return "“\(String((clip.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(120)))”"
        case .image: return "A picture"
        case .file, .folder: return clip.name ?? "A file"
        }
    }

    func phoneCopied(device: String, sources: [ClipDrop.Source], entries: [ClipDrop.Entry], changeCount: Int) {
        let preview: String
        switch sources.count == 1 ? sources.first : nil {
        case let .text(text, _, _): preview = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        case let .file(url, kind, name): preview = kind == .image ? "a photo" : name ?? url.lastPathComponent
        case nil: preview = "\(sources.count) items"
        }
        phoneCopy = PhoneCopy(device: device, preview: preview, entries: entries, at: Date(), changeCount: changeCount)
    }

    func copyPhoneCopy() {
        guard let copy = phoneCopy, let count = remote?.writeClipboard(copy.entries) else { return }
        phoneCopy?.changeCount = count
    }

    // MARK: Panel

    var asks: [Drop] { drops.filter { $0.state == .asking && !$0.isOutgoing } }
    var active: [Drop] { drops.filter(\.state.isActive) }
    var waiting: [Drop] { drops.filter { $0.state == .waiting && $0.isOutgoing } }

    func latestDone(now: Date = Date()) -> Drop? {
        drops.filter { $0.state == .done && now.timeIntervalSince($0.updated) < Self.freshness }.max { $0.updatedAt < $1.updatedAt }
    }

    func freshPhoneCopy(now: Date = Date()) -> PhoneCopy? {
        phoneCopy.flatMap { now.timeIntervalSince($0.at) < Self.freshness ? $0 : nil }
    }

    func freshClipSent(now: Date = Date()) -> ClipSent? {
        clipSent.flatMap { now.timeIntervalSince($0.at) < 120 ? $0 : nil }
    }

    func note(_ title: String, _ body: String, id: String = "vitals.share.\(UUID().uuidString)", category: String? = nil) {
        NotificationManager.shared.send(title: title, body: body, id: id, categoryId: category, quiet: panelOpen)
    }
}
