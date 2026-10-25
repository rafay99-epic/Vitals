import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Watches the general pasteboard and turns each copy into `MacClip`s for the gateway's history.
///
/// `start()` schedules a 0.5 s change-count poll (coalesced with 0.25 s tolerance); `stop()`
/// invalidates it. `RemoteModel` runs it only while the gateway is up and clipboard history is
/// on, so an off watcher has no timer at all. Contents are read only when the count changes,
/// and encoding, thumbnails and file stats run off the main thread.
@MainActor
final class ClipWatcher {
    /// Called on the main actor with the clips one copy produced, in copy order.
    var onClips: (([MacClip]) -> Void)?
    var isRunning: Bool { timer != nil }

    private let directory: URL
    private var timer: Timer?
    private var lastCount = 0
    private var ownWriteCount: Int?
    private var pending: Task<Void, Never>?

    /// `directory` is the shared `clips/` folder the gateway serves bytes from.
    init(directory: URL) { self.directory = directory }

    func start() {
        guard timer == nil else { return }
        lastCount = NSPasteboard.general.changeCount
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = 0.25
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        pending?.cancel()
        pending = nil
    }

    /// Call right after Vitals writes the pasteboard, so its own write isn't recorded as a copy.
    func noteOwnWrite() { ownWriteCount = NSPasteboard.general.changeCount }

    /// True when the user set Vitals to "Deny" under Privacy & Security > Paste from Other Apps.
    static var readsBlocked: Bool {
        if #available(macOS 15.4, *) { return NSPasteboard.general.accessBehavior == .alwaysDeny }
        return false
    }

    func push() async -> [MacClip] {
        let board = NSPasteboard.general
        let front = NSWorkspace.shared.frontmostApplication
        let contents = PasteboardContents.read(board, frontmostBundleID: front?.bundleIdentifier)
        guard let capture = ClipCapture.classify(contents) else { return [] }
        let source = front?.localizedName
        let at = Int64(Date().timeIntervalSince1970 * 1000)
        let directory = directory
        return await Task.detached(priority: .userInitiated) {
            ClipCapture.clips(for: capture, at: at, source: source, directory: directory).map { clip in
                var pushed = clip
                pushed.pushed = true
                return pushed
            }
        }.value
    }

    private func poll() {
        let board = NSPasteboard.general
        let count = board.changeCount
        guard count != lastCount else { return }
        lastCount = count
        guard count != ownWriteCount else { return }
        let front = NSWorkspace.shared.frontmostApplication
        let contents = PasteboardContents.read(board, frontmostBundleID: front?.bundleIdentifier)
        guard let capture = ClipCapture.classify(contents) else { return }
        let source = front?.localizedName
        let at = Int64(Date().timeIntervalSince1970 * 1000)
        let directory = directory
        let previous = pending
        pending = Task { [weak self] in
            await previous?.value
            let clips = await Task.detached(priority: .utility) {
                ClipCapture.clips(for: capture, at: at, source: source, directory: directory)
            }.value
            guard let self, !Task.isCancelled, self.isRunning, !clips.isEmpty else { return }
            self.onClips?(clips)
        }
    }
}

/// What a copy left on the pasteboard, read only as deep as classification needs:
/// file URLs first, then image data, then the string.
struct PasteboardContents: Equatable {
    enum Image: Equatable, Sendable {
        case png(Data)
        case tiff(Data)
    }

    var types: Set<String> = []
    var frontmostBundleID: String?
    var fileURLs: [URL] = []
    var image: Image?
    var string: String?

    /// Reads only flavors the type list advertises. Types and the change count are free to
    /// inspect; content reads are IPC and count as access under macOS pasteboard privacy.
    static func read(_ board: NSPasteboard, frontmostBundleID: String?) -> PasteboardContents {
        let types = Set(board.types?.map(\.rawValue) ?? [])
        var contents = PasteboardContents(types: types, frontmostBundleID: frontmostBundleID)
        guard !ClipCapture.isPrivate(contents) else { return contents }
        if types.contains(NSPasteboard.PasteboardType.fileURL.rawValue) {
            let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
            contents.fileURLs = board.readObjects(forClasses: [NSURL.self], options: options) as? [URL] ?? []
            if !contents.fileURLs.isEmpty { return contents }
        }
        if !ClipCapture.prefersText(contents) {
            if types.contains(NSPasteboard.PasteboardType.png.rawValue), let png = board.data(forType: .png) {
                contents.image = .png(png)
                return contents
            }
            if types.contains(NSPasteboard.PasteboardType.tiff.rawValue), let tiff = board.data(forType: .tiff) {
                contents.image = .tiff(tiff)
                return contents
            }
        }
        if types.contains(NSPasteboard.PasteboardType.string.rawValue) { contents.string = board.string(forType: .string) }
        return contents
    }
}

/// Classifies a copy and builds its clips. Pure apart from `clips(for:)`, which writes into `clips/`.
enum ClipCapture: Equatable, Sendable {
    case files([URL])
    case image(PasteboardContents.Image)
    case link(String)
    case text(String)

    /// Marker types password managers and other apps set to say "don't record this" (nspasteboard.org).
    static let privateTypes: Set<String> = [
        "org.nspasteboard.ConcealedType",
        "org.nspasteboard.TransientType",
        "org.nspasteboard.AutoGeneratedType",
        "com.agilebits.onepassword",
        "de.petermaurer.TransientPasteboardType"
    ]

    /// Copies made while one of these is in front are never recorded.
    static let ignoredApps: Set<String> = [
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop",
        "com.apple.Passwords",
        "com.apple.keychainaccess"
    ]

    static let maxFiles = 20
    static let maxStringBytes = 10 * 1024 * 1024
    /// Mirrors `CLIP_LIMITS` in clips.ts.
    static let inlineTextBytes = 256 * 1024
    static let previewCharacters = 4 * 1024
    static let thumbChars = 48 * 1024
    static let thumbPixels = 256
    static let folderWalkCap = 10_000

    static func isPrivate(_ contents: PasteboardContents) -> Bool {
        !contents.types.isDisjoint(with: privateTypes) || contents.frontmostBundleID.map(ignoredApps.contains) == true
    }

    /// Office and iWork put a picture of the selection next to the text. RTF on the pasteboard
    /// means it was a text copy; browsers' "Copy Image" never carries RTF.
    static func prefersText(_ contents: PasteboardContents) -> Bool {
        contents.types.contains(NSPasteboard.PasteboardType.rtf.rawValue)
            && contents.types.contains(NSPasteboard.PasteboardType.string.rawValue)
    }

    /// nil means "don't record": private, empty, or too big.
    static func classify(_ contents: PasteboardContents) -> ClipCapture? {
        guard !isPrivate(contents) else { return nil }
        if !contents.fileURLs.isEmpty { return .files(Array(contents.fileURLs.prefix(maxFiles))) }
        if let image = contents.image { return .image(image) }
        guard let string = contents.string, string.utf8.count <= maxStringBytes else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return isLink(trimmed) ? .link(trimmed) : .text(string)
    }

    /// One http(s) URL and nothing else.
    static func isLink(_ string: String) -> Bool {
        guard !string.contains(where: \.isWhitespace),
              let url = URL(string: string),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host?.isEmpty == false
        else { return false }
        return true
    }

    static func newID() -> String { UUID().uuidString.lowercased() }

    /// Builds the history entries for one copy. Images and long text are written into
    /// `directory` here; files and folders are only described (cloned or zipped on first download).
    static func clips(for capture: ClipCapture, at: Int64, source: String?, directory: URL) -> [MacClip] {
        switch capture {
        case let .files(urls):
            return urls.compactMap { fileClip($0, at: at, source: source) }
        case let .image(image):
            return imageClip(image, at: at, source: source, directory: directory).map { [$0] } ?? []
        case let .link(url):
            return [MacClip(id: newID(), kind: .link, at: at, source: source, text: url)]
        case let .text(text):
            return textClip(text, at: at, source: source, directory: directory).map { [$0] } ?? []
        }
    }

    private static func fileClip(_ url: URL, at: Int64, source: String?) -> MacClip? {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey]) else { return nil }
        let isFolder = values.isDirectory == true
        return MacClip(
            id: newID(),
            kind: isFolder ? .folder : .file,
            at: at,
            source: source,
            name: url.lastPathComponent,
            mime: isFolder ? nil : UTType(filenameExtension: url.pathExtension)?.preferredMIMEType,
            bytes: isFolder ? 0 : values.fileSize ?? 0,
            files: isFolder ? fileCount(in: url) : nil,
            origin: url.path
        )
    }

    private static func imageClip(_ image: PasteboardContents.Image, at: Int64, source: String?, directory: URL) -> MacClip? {
        let png: Data
        switch image {
        case let .png(data): png = data
        case let .tiff(data):
            guard let converted = encode(data, as: .png) else { return nil }
            png = converted
        }
        let id = newID()
        let stored = "\(id).png"
        guard write(png, to: directory.appendingPathComponent(stored)) else { return nil }
        return MacClip(id: id, kind: .image, at: at, source: source, mime: "image/png", bytes: png.count, thumb: thumbnail(png), stored: stored)
    }

    private static func textClip(_ text: String, at: Int64, source: String?, directory: URL) -> MacClip? {
        let data = Data(text.utf8)
        guard data.count > inlineTextBytes else { return MacClip(id: newID(), kind: .text, at: at, source: source, text: text) }
        let id = newID()
        let stored = "\(id).txt"
        guard write(data, to: directory.appendingPathComponent(stored)) else { return nil }
        return MacClip(
            id: id, kind: .text, at: at, source: source,
            text: String(text.prefix(previewCharacters)), truncated: true,
            mime: "text/plain", bytes: data.count, stored: stored
        )
    }

    /// Regular files under `url`, walking at most `folderWalkCap` entries.
    static func fileCount(in url: URL) -> Int {
        guard let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey]) else { return 0 }
        var walked = 0
        var files = 0
        while walked < folderWalkCap, let item = walker.nextObject() as? URL {
            walked += 1
            if (try? item.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true { files += 1 }
        }
        return files
    }

    /// A base64 JPEG at most `thumbPixels` on its long side, lowering quality until it fits `thumbChars`.
    static func thumbnail(_ data: Data) -> String? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbPixels
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        for quality in [0.7, 0.5, 0.3, 0.15] {
            guard let jpeg = encode(image, as: .jpeg, quality: quality) else { return nil }
            let base64 = jpeg.base64EncodedString()
            if base64.count <= thumbChars { return base64 }
        }
        return nil
    }

    private static func encode(_ data: Data, as type: UTType) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        return encode(image, as: type)
    }

    private static func encode(_ image: CGImage, as type: UTType, quality: Double? = nil) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil) else { return nil }
        let properties = quality.map { [kCGImageDestinationLossyCompressionQuality: $0] as CFDictionary }
        CGImageDestinationAddImage(destination, image, properties)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }

    private static func write(_ data: Data, to url: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            Log.notice(.remote, "couldn't store a clip at \(url.lastPathComponent)", error: error)
            return false
        }
    }
}
