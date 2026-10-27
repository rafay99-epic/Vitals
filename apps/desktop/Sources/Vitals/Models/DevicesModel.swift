import AppKit
import Foundation

/// What each phone's page in the sidebar's Devices group shows: its newest files by kind,
/// its folders, what it sent to the clipboard, and thumbnails. Cached per device, so pages
/// reopen filled and a phone that went away stays listed until it's back.
@MainActor
@Observable
final class DevicesModel {
    struct Recent {
        var entries: [PhoneEntry] = []
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

    struct Folder {
        var listing: PhoneListing?
        var problem: String?
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
    }

    /// Phones with Files on, from the gateway, with whether each answers right now.
    private(set) var phones: [PhoneDevice] = []
    private(set) var pages: [String: Page] = [:]
    private(set) var thumbs: [String: NSImage] = [:]

    @ObservationIgnored weak var remote: RemoteModel?
    @ObservationIgnored private var thumbsAsked: Set<String> = []

    /// `FS_LIMITS.thumbs`: the most paths one FsThumbs call takes.
    static let thumbBatch = 24
    static let pollInterval: Duration = .seconds(4)

    func phone(_ id: String) -> PhoneDevice? { phones.first { $0.id == id } }

    func page(_ id: String) -> Page { pages[id] ?? Page() }

    func thumb(_ device: String, _ path: String) -> NSImage? { thumbs[Self.key(device, path)] }

    /// Every listed item of `kinds`, merged newest first.
    func newest(_ id: String, _ kinds: [RecentKind]) -> [PhoneEntry] {
        let recent = page(id).recent
        return kinds.flatMap { recent[$0]?.entries ?? [] }.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    /// Phones a transfer from `id` can go to: every other phone with Files on.
    func destinations(from id: String) -> [PhoneDevice] { phones.filter { $0.id != id } }

    func reset() {
        phones = []
        pages = [:]
        thumbs = [:]
        thumbsAsked = []
    }

    /// Keeps the last list when the gateway can't answer, so the sidebar doesn't flicker on a restart.
    /// A phone that comes back online reloads its page if it was opened before.
    func refreshPhones() async {
        guard let remote, remote.isEnabled, let next = try? await remote.phoneDevices() else { return }
        let wasOnline = Set(phones.filter(\.online).map(\.id))
        if next != phones { phones = next }
        for phone in next where phone.online && !wasOnline.contains(phone.id) && pages[phone.id] != nil {
            Task { await load(phone.id) }
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
            recent.entries = (more ? recent.entries : []) + (answer?.entries ?? [])
            recent.more = answer?.more ?? false
            recent.loaded = true
            recent.problem = nil
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
        } catch {
            pages[id, default: Page()].rootsProblem = Self.message(error)
        }
    }

    /// Lists one folder, keeping the last listing on screen until the new one lands.
    func loadFolder(_ id: String, path: String) async {
        guard let remote else { return }
        do {
            let listing = try await remote.phoneList(id, path: path)
            pages[id, default: Page()].folders[path] = Folder(listing: listing)
        } catch {
            pages[id, default: Page()].folders[path, default: Folder()].problem = Self.message(error)
        }
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
        } catch {
            pages[id, default: Page()].clipsProblem = Self.message(error)
        }
    }

    /// Asks for thumbnails not yet cached, in batches the gateway accepts. Each path is asked once
    /// unless the phone didn't answer.
    func loadThumbs(_ device: String, paths: [String]) async {
        guard let remote else { return }
        let missing = paths.filter { thumbsAsked.insert(Self.key(device, $0)).inserted }
        for start in stride(from: 0, to: missing.count, by: Self.thumbBatch) {
            let batch = Array(missing[start..<min(start + Self.thumbBatch, missing.count)])
            guard !Task.isCancelled, let answer = try? await remote.phoneThumbs(device, paths: batch) else {
                missing[start...].forEach { thumbsAsked.remove(Self.key(device, $0)) }
                return
            }
            let decoded = await Task.detached(priority: .utility) {
                answer.compactMap { thumb in thumb.jpeg.flatMap { Data(base64Encoded: $0) }.map { (thumb.path, $0) } }
            }.value
            var fresh: [String: NSImage] = [:]
            for (path, data) in decoded { fresh[Self.key(device, path)] = NSImage(data: data) }
            thumbs.merge(fresh) { $1 }
        }
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

    private static func message(_ error: Error) -> String {
        (error as? RemoteModel.AdminFailure)?.message ?? (error as? ClipDrop.Failure)?.message ?? "That phone didn't answer"
    }
}
