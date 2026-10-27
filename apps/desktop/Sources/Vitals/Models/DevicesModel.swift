import AppKit
import Foundation
import ImageIO

/// What each phone's page in the sidebar's Devices group shows: its newest files by kind,
/// its folders, what it sent to the clipboard, and thumbnails. Cached per device, so pages
/// reopen filled and a phone that went away stays listed until it's back.
@MainActor
@Observable
final class DevicesModel {
    /// A phone's file with what its row shows worked out once, off the main thread.
    struct Item: Identifiable, Equatable, Sendable {
        let entry: PhoneEntry
        let symbol: String
        /// "245 KB · Yesterday".
        let detail: String
        var id: String { entry.path }
        var name: String { entry.name }
        var path: String { entry.path }
        var isImage: Bool { symbol == "photo" }

        init(_ entry: PhoneEntry) {
            self.entry = entry
            symbol = DropLook.symbol(name: entry.name)
            detail = "\(ShareFormat.size(Int(entry.size))) · \(DropLook.when(Date(timeIntervalSince1970: TimeInterval(entry.modifiedAt) / 1000)))"
        }

        static func make(_ entries: [PhoneEntry]) async -> [Item] {
            await Task.detached(priority: .userInitiated) { entries.map(Item.init) }.value
        }
    }

    struct Recent {
        var entries: [Item] = []
        var more = false
        var loaded = false
        var loading = false
        var problem: String?
    }

    struct ClipRow: Identifiable {
        let item: PhoneClip
        let thumb: NSImage?
        var id: String { item.id }
    }

    /// A folder as far as it's loaded. FsList sorts folders first, so pages fill the
    /// sections in order.
    struct Folder {
        var folders: [PhoneRoot] = []
        var images: [Item] = []
        var files: [Item] = []
        /// Entries loaded so far: the offset of the next page.
        var loaded = 0
        /// nil until the first page lands.
        var total: Int?
        var loading = false
        var problem: String?
        var more: Bool { (total ?? 0) > loaded }
    }

    /// A Quick Look preview on its way from the phone, or why it couldn't come.
    enum Preview: Equatable {
        case getting(String)
        case failed(String)
    }

    struct Page {
        var recent: [RecentKind: Recent] = [:]
        var roots: [PhoneRoot]?
        var rootsProblem: String?
        /// Listings by folder path, so going back up shows them at once.
        var folders: [String: Folder] = [:]
        var clips: [ClipRow]?
        var clipsProblem: String?
        var copied: String?
        var notice: String?
        var preview: Preview?
    }

    /// One thumbnail, observed on its own so a batch landing redraws only its tiles.
    @MainActor
    @Observable
    final class Thumb {
        var image: NSImage?
    }

    /// Phones with Files on, from the gateway, with whether each answers right now.
    private(set) var phones: [PhoneDevice] = []
    private(set) var pages: [String: Page] = [:]

    @ObservationIgnored weak var remote: RemoteModel?
    @ObservationIgnored private var thumbs: [String: Thumb] = [:]
    @ObservationIgnored private var thumbsAsked: Set<String> = []
    /// How many tiles show each thumbnail right now.
    @ObservationIgnored private var thumbsOnScreen: [String: Int] = [:]
    @ObservationIgnored private var thumbQueue: [String] = []
    @ObservationIgnored private var thumbPump: Task<Void, Never>?
    @ObservationIgnored private var previewTask: Task<Void, Never>?
    @ObservationIgnored private var previewCopies: [String: URL] = [:]

    /// `FS_LIMITS.thumbs`: the most paths one FsThumbs call takes.
    static let thumbBatch = 24
    static let pollInterval: Duration = .seconds(4)

    func phone(_ id: String) -> PhoneDevice? { phones.first { $0.id == id } }

    func page(_ id: String) -> Page { pages[id] ?? Page() }

    func thumb(_ device: String, _ path: String) -> NSImage? { slot(Self.key(device, path)).image }

    /// Every listed item of `kinds`, merged newest first.
    func newest(_ id: String, _ kinds: [RecentKind]) -> [Item] {
        let recent = page(id).recent
        return kinds.flatMap { recent[$0]?.entries ?? [] }.sorted { $0.entry.modifiedAt > $1.entry.modifiedAt }
    }

    /// Phones a transfer from `id` can go to: every other phone with Files on.
    func destinations(from id: String) -> [PhoneDevice] { phones.filter { $0.id != id } }

    func reset() {
        phones = []
        pages = [:]
        thumbs.values.forEach { $0.image = nil }
        thumbs = [:]
        thumbsAsked = []
        thumbQueue = []
        thumbPump?.cancel()
        thumbPump = nil
        previewTask?.cancel()
        previewCopies = [:]
    }

    /// Keeps the last list when the gateway can't answer, so the sidebar doesn't flicker on a restart.
    /// A phone that comes back online reloads its page if it was opened before, and the thumbnails
    /// on screen ask again.
    func refreshPhones() async {
        guard let remote, remote.isEnabled, let next = try? await remote.phoneDevices() else { return }
        let wasOnline = Set(phones.filter(\.online).map(\.id))
        if next != phones { phones = next }
        for phone in next where phone.online && !wasOnline.contains(phone.id) {
            if pages[phone.id] != nil { Task { await load(phone.id) } }
            thumbsOnScreen.keys.filter { Self.device(of: $0) == phone.id }.forEach(queueThumb)
        }
    }

    /// While a device's page is on screen: loads it, then keeps online state fresh so a phone
    /// that opens Vitals fills in without a click. Ends when the page's task is cancelled.
    func watch(_ id: String) async {
        await load(id)
        while !Task.isCancelled {
            try? await Task.sleep(for: Self.pollInterval)
            guard !Task.isCancelled else { return }
            await refreshPhones()
        }
    }

    /// Clipboard comes from the gateway's history, so it loads even while the phone is away.
    func load(_ id: String) async {
        if pages[id] == nil { pages[id] = Page() }
        let online = phone(id)?.online == true
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadClips(id) }
            if online {
                for kind in RecentKind.allCases { group.addTask { await self.loadRecent(id, kind) } }
                group.addTask { await self.loadRoots(id) }
            }
        }
    }

    /// First page, or with `more` the next page after what's listed.
    func loadRecent(_ id: String, _ kind: RecentKind, more: Bool = false) async {
        guard let remote, pages[id]?.recent[kind]?.loading != true else { return }
        var recent = pages[id]?.recent[kind] ?? Recent()
        let offset = more ? recent.entries.count : 0
        recent.loading = true
        pages[id, default: Page()].recent[kind] = recent
        do {
            let answer = try await remote.phoneRecent(id, kind: kind, offset: offset)
            let items = await Item.make(answer?.entries ?? [])
            recent.entries = (more ? recent.entries : []) + items
            recent.more = answer?.more ?? false
            recent.loaded = true
            recent.problem = nil
        } catch is CancellationError {
        } catch {
            recent.problem = Self.message(error)
        }
        recent.loading = false
        pages[id, default: Page()].recent[kind] = recent
    }

    func loadRoots(_ id: String) async {
        guard let remote else { return }
        do {
            pages[id, default: Page()].roots = try await remote.phoneRoots(id)
            pages[id]?.rootsProblem = nil
        } catch is CancellationError {
        } catch {
            pages[id, default: Page()].rootsProblem = Self.message(error)
        }
    }

    /// Lists a folder's first page, keeping the last listing on screen until it lands, or with
    /// `more` the next page after what's loaded.
    func loadFolder(_ id: String, path: String, more: Bool = false) async {
        guard let remote, pages[id]?.folders[path]?.loading != true else { return }
        var folder = pages[id]?.folders[path] ?? Folder()
        if more, !folder.more { return }
        let offset = more ? folder.loaded : 0
        folder.loading = true
        pages[id, default: Page()].folders[path] = folder
        do {
            let listing = try await remote.phoneList(id, path: path, offset: offset)
            let entries = listing?.entries ?? []
            let items = await Item.make(entries.filter { $0.kind != "folder" })
            if !more { folder = Folder(loading: true) }
            folder.folders += entries.lazy.filter { $0.kind == "folder" }.map { PhoneRoot(label: $0.name, path: $0.path, place: "folder") }
            folder.images += items.filter(\.isImage)
            folder.files += items.filter { !$0.isImage }
            folder.loaded = offset + entries.count
            folder.total = max(listing?.total ?? 0, folder.loaded)
            folder.problem = nil
        } catch is CancellationError {
        } catch {
            folder.problem = Self.message(error)
        }
        folder.loading = false
        pages[id, default: Page()].folders[path] = folder
    }

    func loadClips(_ id: String) async {
        guard let remote else { return }
        do {
            let items = try await remote.phoneClips(id)
            let images = await Task.detached(priority: .utility) {
                items.map { $0.clip.thumb.flatMap { Data(base64Encoded: $0) } }
            }.value
            pages[id, default: Page()].clips = zip(items, images).map { ClipRow(item: $0, thumb: $1.flatMap(NSImage.init(data:))) }
            pages[id]?.clipsProblem = nil
        } catch is CancellationError {
        } catch {
            pages[id, default: Page()].clipsProblem = Self.message(error)
        }
    }

    /// A tile showing `path` came on screen. Thumbnails asked for around the same time go
    /// together, at most `thumbBatch` per call.
    func showThumb(_ device: String, _ path: String) {
        let key = Self.key(device, path)
        thumbsOnScreen[key, default: 0] += 1
        guard thumbsOnScreen[key] == 1, phone(device)?.online == true else { return }
        queueThumb(key)
    }

    /// The tile scrolled away. A thumbnail not asked for yet is skipped.
    func hideThumb(_ device: String, _ path: String) {
        let key = Self.key(device, path)
        guard let count = thumbsOnScreen[key] else { return }
        thumbsOnScreen[key] = count > 1 ? count - 1 : nil
    }

    private func slot(_ key: String) -> Thumb {
        if let slot = thumbs[key] { return slot }
        let slot = Thumb()
        thumbs[key] = slot
        return slot
    }

    private func queueThumb(_ key: String) {
        guard !thumbsAsked.contains(key), thumbs[key]?.image == nil else { return }
        thumbQueue.append(key)
        if thumbPump == nil { thumbPump = Task { await pumpThumbs() } }
    }

    /// Waits a beat so tiles appearing together share a call, then asks for what's still on
    /// screen, one device's batch at a time.
    private func pumpThumbs() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(50))
            thumbQueue.removeAll { thumbsOnScreen[$0] == nil || thumbsAsked.contains($0) }
            guard let first = thumbQueue.first else { break }
            let device = Self.device(of: first)
            var batch: [String] = []
            var rest: [String] = []
            for key in thumbQueue {
                if batch.count < Self.thumbBatch, Self.device(of: key) == device { batch.append(key) } else { rest.append(key) }
            }
            thumbQueue = rest
            await loadThumbs(device, paths: batch.map { String($0.dropFirst(device.count + 1)) })
        }
        thumbPump = nil
    }

    /// Each path is asked once unless the phone didn't answer. JPEGs decode off the main thread.
    private func loadThumbs(_ device: String, paths: [String]) async {
        guard let remote else { return }
        let missing = paths.filter { thumbsAsked.insert(Self.key(device, $0)).inserted }
        guard !missing.isEmpty else { return }
        guard let answer = try? await remote.phoneThumbs(device, paths: missing) else {
            missing.forEach { thumbsAsked.remove(Self.key(device, $0)) }
            return
        }
        let decoded = await Task.detached(priority: .utility) {
            answer.compactMap { thumb -> (String, CGImage)? in
                guard let data = thumb.jpeg.flatMap({ Data(base64Encoded: $0) }),
                      let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
                else { return nil }
                return (thumb.path, image)
            }
        }.value
        for (path, image) in decoded {
            slot(Self.key(device, path)).image = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        }
    }

    /// Copies `items` from the phone one at a time and shows them in Quick Look as they land,
    /// so the first opens without waiting for the rest. Closing the panel stops the copying.
    /// False when there's no file to preview.
    @discardableResult
    func preview(_ id: String, _ items: [Item]) -> Bool {
        let files = items.filter { $0.entry.kind != "folder" }
        guard let remote, !files.isEmpty else { return false }
        previewTask?.cancel()
        PreviewPanel.shared.close()
        previewTask = Task { [weak self] in
            var shown = false
            var problem: String?
            for item in files {
                guard let model = self, !Task.isCancelled else { return }
                if !shown { model.pages[id, default: Page()].preview = .getting(item.name) }
                do {
                    let url = try await model.localCopy(id, item, remote)
                    guard !Task.isCancelled else { return }
                    if shown {
                        PreviewPanel.shared.append(url)
                    } else {
                        shown = true
                        model.pages[id]?.preview = nil
                        PreviewPanel.shared.show([url]) { [weak model] in model?.previewTask?.cancel() }
                    }
                } catch is CancellationError {
                    return
                } catch {
                    problem = Self.message(error)
                }
            }
            if let problem { self?.pages[id]?.preview = .failed(problem) }
        }
        return true
    }

    /// Stops a preview on its way, or clears why one failed.
    func cancelPreview(_ id: String) {
        if case .getting = pages[id]?.preview { previewTask?.cancel() }
        pages[id]?.preview = nil
    }

    /// The Mac's copy of a phone file, reused while the gateway still has it and the file is unchanged.
    private func localCopy(_ id: String, _ item: Item, _ remote: RemoteModel) async throws -> URL {
        let key = "\(Self.key(id, item.path))\u{0}\(item.entry.modifiedAt)\u{0}\(item.entry.size)"
        if let url = previewCopies[key], FileManager.default.fileExists(atPath: url.path) { return url }
        guard let url = try await remote.phonePreview(id, path: item.path) else { throw RemoteModel.AdminFailure(message: "That phone didn't answer") }
        previewCopies[key] = url
        return url
    }

    /// Asks the phone to send `paths` over Drop: to this Mac, where received files land, or
    /// on to the phone `to`. It keeps its copy.
    func transfer(_ id: String, paths: [String], to target: PhoneDevice?) async {
        guard let remote, !paths.isEmpty else { return }
        let what = paths.count == 1 ? "1 file" : "\(paths.count) files"
        do {
            _ = try await remote.pullFromPhone(id, paths: paths, to: target?.id)
            pages[id, default: Page()].notice = target.map { "Sending \(what) to \($0.name)" } ?? "Getting \(what) to this Mac"
        } catch {
            pages[id, default: Page()].notice = Self.message(error)
        }
    }

    /// Puts a clip on the Mac clipboard so ⌘V works anywhere.
    func copy(_ id: String, _ row: ClipRow) async {
        guard let remote, let phone = phone(id) else { return }
        do {
            try await remote.copyPhoneClip(row.item, deviceName: phone.name)
            pages[id, default: Page()].copied = row.id
        } catch {
            pages[id, default: Page()].notice = Self.message(error)
        }
    }

    private static func key(_ device: String, _ path: String) -> String { "\(device)\u{0}\(path)" }

    private static func device(of key: String) -> String { String(key.prefix { $0 != "\u{0}" }) }

    private static func message(_ error: Error) -> String {
        (error as? RemoteModel.AdminFailure)?.message ?? (error as? ClipDrop.Failure)?.message ?? "That phone didn't answer"
    }
}
