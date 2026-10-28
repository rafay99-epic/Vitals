import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Moves clip bytes in and out of the shared `clips/` folder: clones or zips a copied file or
/// folder so phones can download it, and places what phones send on the clipboard or in
/// Downloads. Everything here except `write(_:)` is file work meant to run off the main thread.
enum ClipDrop {
    struct Failure: Error, Equatable {
        let message: String
        init(_ message: String) { self.message = message }
    }

    /// What `materialize` left in `clips/`.
    struct Materialized: Equatable, Sendable {
        let stored: String
        let bytes: Int
        let files: Int?
    }

    /// One validated placement, read from `clips/` when it needs to be.
    enum Source: Equatable, Sendable {
        case text(String, kind: ClipKind, name: String?)
        case file(URL, kind: ClipKind, name: String?)

        var kind: ClipKind {
            switch self {
            case let .text(_, kind, _), let .file(_, kind, _): return kind
            }
        }
    }

    /// A pasteboard item built off-main; `write(_:)` turns it into AppKit objects.
    enum Entry: Equatable, Sendable {
        case string(String)
        case data(Data, type: String)
        case file(URL)
    }

    /// Mirrors `CLIP_LIMITS.itemBytes`.
    static let itemBytes = 1024 * 1024 * 1024

    /// `ClipId` in clips.ts.
    static func isValidID(_ id: String) -> Bool {
        id.wholeMatch(of: #/[A-Za-z0-9-]{8,64}/#) != nil
    }

    /// `directory/<name>` when `name` is a bare `ClipFileName` (`<id>.<ext>`, never a path), else nil.
    static func storedURL(_ name: String, in directory: URL) -> URL? {
        guard name.wholeMatch(of: #/[A-Za-z0-9-]{8,64}(\.[a-z0-9]{1,8}){1,2}/#) != nil else { return nil }
        let url = directory.appendingPathComponent(name).standardizedFileURL
        return url.deletingLastPathComponent().path == directory.standardizedFileURL.path ? url : nil
    }

    // MARK: Mac to phone

    /// Clones a copied file (free on APFS) or zips a copied folder into `clips/<id>.<ext>`.
    static func materialize(id: String, kind: ClipKind, origin: String, into directory: URL) throws -> Materialized {
        guard isValidID(id), kind == .file || kind == .folder, origin.hasPrefix("/") else {
            throw Failure("That clip can't be downloaded")
        }
        let fileManager = FileManager.default
        var isFolder: ObjCBool = false
        guard fileManager.fileExists(atPath: origin, isDirectory: &isFolder), isFolder.boolValue == (kind == .folder) else {
            throw Failure(kind == .folder ? "That folder is no longer on the Mac" : "That file is no longer on the Mac")
        }
        let source = URL(fileURLWithPath: origin)
        if kind == .file, size(of: source) > itemBytes { throw Failure("That file is over 1 GB, too big to send") }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let stored = "\(id).\(kind == .folder ? "zip" : safeExtension(source.pathExtension))"
        let target = directory.appendingPathComponent(stored)
        // Built under a hidden name, then renamed into place, so a reader never sees half a file.
        let partial = directory.appendingPathComponent(".\(id)-\(UUID().uuidString).partial")
        defer { try? fileManager.removeItem(at: partial) }
        do {
            if kind == .folder { try zip(source, to: partial) } else { try fileManager.copyItem(at: source, to: partial) }
        } catch {
            Log.notice(.remote, "couldn't materialize clip \(id)", error: error)
            throw Failure(kind == .folder ? "Couldn't zip that folder" : "Couldn't read that file")
        }
        let bytes = size(of: partial)
        guard bytes <= itemBytes else { throw Failure("That folder zips to over 1 GB, too big to send") }
        guard rename(partial.path, target.path) == 0 else { throw Failure("Couldn't store that clip") }
        return Materialized(stored: stored, bytes: bytes, files: kind == .folder ? ClipCapture.fileCount(in: source) : nil)
    }

    private static func zip(_ folder: URL, to archive: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--norsrc", "--noextattr", "--noqtn", "--keepParent", folder.path, archive.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw Failure("ditto exited \(process.terminationStatus)") }
    }

    /// The file's own extension when it fits `ClipFileName`, else `bin`.
    static func safeExtension(_ ext: String) -> String {
        let lower = ext.lowercased()
        return lower.wholeMatch(of: #/[a-z0-9]{1,8}/#) != nil ? lower : "bin"
    }

    private static func size(of url: URL) -> Int {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
    }

    // MARK: Phone to Mac

    /// Checks every placement before anything is written: one bad `stored` name fails the batch.
    static func resolve(_ items: [ClipPlacement], in directory: URL) throws -> [Source] {
        try items.map { item in
            let file = try item.stored.map { name -> URL in
                guard let url = storedURL(name, in: directory) else { throw Failure("A clip had an invalid file name") }
                guard FileManager.default.fileExists(atPath: url.path) else { throw Failure("A clip is no longer stored on the Mac") }
                return url
            }
            switch item.kind {
            case .text, .link:
                if let file {
                    guard let text = try? String(contentsOf: file, encoding: .utf8) else { throw Failure("Couldn't read a text clip") }
                    return .text(text, kind: item.kind, name: item.name)
                }
                guard let text = item.text else { throw Failure("A text clip had no text") }
                return .text(text, kind: item.kind, name: item.name)
            case .image, .file, .folder:
                guard let file else { throw Failure("A clip had no file") }
                return .file(file, kind: item.kind, name: item.name)
            }
        }
    }

    /// Copies into `downloads` (or a sanitized `folder` inside it), never overwriting.
    /// Text and links become `.txt` files. Returns the saved files.
    @discardableResult
    static func save(_ sources: [Source], to downloads: URL, folder: String?, deviceName: String) throws -> [URL] {
        let fileManager = FileManager.default
        let destination = sanitize(folder).map { downloads.appendingPathComponent($0, isDirectory: true) } ?? downloads
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        return try sources.map { source in
            let target = uniqueURL(for: fileName(for: source, deviceName: deviceName), in: destination)
            do {
                switch source {
                case let .text(text, _, _): try Data(text.utf8).write(to: target, options: .withoutOverwriting)
                case let .file(url, _, _): try fileManager.copyItem(at: url, to: target)
                }
            } catch {
                Log.notice(.remote, "couldn't save a clip to \(target.path)", error: error, report: false)
                throw Failure("Couldn't save to \(destination.lastPathComponent)")
            }
            quarantine(target)
            return target
        }
    }

    /// Marks a file that came from a phone like a browser download, so Gatekeeper checks it before it runs.
    static func quarantine(_ url: URL) {
        let value = String(format: "0081;%08x;Vitals;", Int(Date().timeIntervalSince1970))
        _ = value.withCString { setxattr(url.path, "com.apple.quarantine", $0, strlen($0), 0, 0) }
    }

    /// Pasteboard entries for a batch: text as strings, images as image data, and files
    /// copied into `downloads` first so the pasteboard points at something that stays.
    static func clipboardEntries(_ sources: [Source], downloads: URL, deviceName: String) throws -> [Entry] {
        try sources.map { source in
            switch source {
            case let .text(text, _, _): return .string(text)
            case let .file(url, .image, _):
                if let entry = imageEntry(url) { return entry }
                return .file(try save([source], to: downloads, folder: nil, deviceName: deviceName)[0])
            case .file:
                return .file(try save([source], to: downloads, folder: nil, deviceName: deviceName)[0])
            }
        }
    }

    /// PNG and JPEG go on as-is; other formats (HEIC from phones) are converted to PNG.
    private static func imageEntry(_ url: URL) -> Entry? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let type = UTType(filenameExtension: url.pathExtension)
        if let type, type.conforms(to: .png) || type.conforms(to: .jpeg) { return .data(data, type: type.identifier) }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? .data(output as Data, type: UTType.png.identifier) : nil
    }

    /// Replaces the general pasteboard with `entries`. Callers set the watcher's echo guard after.
    @MainActor
    static func write(_ entries: [Entry]) -> Bool {
        let objects: [NSPasteboardWriting] = entries.map { entry in
            switch entry {
            case let .string(text): return text as NSString
            case let .file(url): return url as NSURL
            case let .data(data, type):
                let item = NSPasteboardItem()
                item.setData(data, forType: NSPasteboard.PasteboardType(type))
                return item
            }
        }
        let board = NSPasteboard.general
        board.clearContents()
        return board.writeObjects(objects)
    }

    // MARK: Names

    /// A Finder-safe single path component, or nil when nothing usable is left.
    static func sanitize(_ name: String?) -> String? {
        guard let name else { return nil }
        let unsafe = CharacterSet(charactersIn: "/:\\").union(.controlCharacters)
        var cleaned = name.components(separatedBy: unsafe).joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        while cleaned.hasPrefix(".") { cleaned.removeFirst() }
        cleaned = String(cleaned.prefix(200)).trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? nil : cleaned
    }

    /// `name` in `folder`, or "name 2.ext", "name 3.ext"... when taken.
    static func uniqueURL(for name: String, in folder: URL, exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = folder.appendingPathComponent(name)
        var number = 2
        while exists(candidate) {
            candidate = folder.appendingPathComponent(ext.isEmpty ? "\(base) \(number)" : "\(base) \(number).\(ext)")
            number += 1
        }
        return candidate
    }

    static func fileName(for source: Source, deviceName: String) -> String {
        let device = sanitize(deviceName) ?? "phone"
        switch source {
        case let .text(_, kind, name):
            let fallback = kind == .link ? "Link from \(device)" : "Text from \(device)"
            let base = sanitize(name) ?? fallback
            return (base as NSString).pathExtension.lowercased() == "txt" ? base : "\(base).txt"
        case let .file(url, kind, name):
            let ext = url.pathExtension
            guard let base = sanitize(name) else {
                return kind == .image ? "Photo from \(device).\(ext)" : url.lastPathComponent
            }
            return (base as NSString).pathExtension.isEmpty && !ext.isEmpty ? "\(base).\(ext)" : base
        }
    }

    /// The notification after a drop, e.g. "Got 2 photos from Pixel 9 Pro" / "They're on your clipboard."
    static func summary(_ kinds: [ClipKind], to destination: ClipDestination, folder: String?, deviceName: String) -> (title: String, body: String) {
        let count = kinds.count
        let what: String
        switch Set(kinds).count == 1 ? kinds.first : nil {
        case .image: what = count == 1 ? "a photo" : "\(count) photos"
        case .file, .folder: what = count == 1 ? "a file" : "\(count) files"
        case .link: what = count == 1 ? "a link" : "\(count) links"
        case .text: what = count == 1 ? "text" : "\(count) texts"
        case nil: what = count == 1 ? "an item" : "\(count) items"
        }
        let pronoun = count == 1 ? "It's" : "They're"
        switch destination {
        case .clipboard:
            let hasFiles = kinds.contains { $0 == .file || $0 == .folder }
            return ("Got \(what) from \(deviceName)", "\(pronoun) on your clipboard\(hasFiles ? " and in Downloads" : "").")
        case .downloads:
            let place = sanitize(folder).map { "Downloads/\($0)" } ?? "Downloads"
            return ("Saved \(what) from \(deviceName)", "\(pronoun) in \(place).")
        }
    }
}
