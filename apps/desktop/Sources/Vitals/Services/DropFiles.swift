import AppKit
import UniformTypeIdentifiers

enum DropFiles {
    struct Failure: Error, Equatable {
        let message: String
        init(_ message: String) { self.message = message }
    }

    struct Item: Equatable, Identifiable, Sendable {
        let url: URL
        let files: [MacDropFile]
        var id: URL { url }
        var name: String { url.lastPathComponent }
        var bytes: Int { files.reduce(0) { $0 + $1.size } }
        var isFolder: Bool { files.first?.path != nil }
    }

    struct Placed: Equatable, Sendable {
        let items: [URL]
        let files: Int
        let bytes: Int
        let failed: Int
    }

    enum AppKind: Equatable, Sendable { case mac, android }

    static let maxFiles = 10_000
    static let skipped: Set<String> = [".DS_Store"]

    static func expand(_ url: URL) throws -> Item {
        let fileManager = FileManager.default
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey])
        guard let values else { throw Failure("\(url.lastPathComponent) is no longer there") }
        if values.isDirectory != true {
            guard values.isRegularFile == true else { throw Failure("\(url.lastPathComponent) can't be sent") }
            return Item(url: url, files: [file(url, path: nil, size: values.fileSize ?? 0)])
        }
        let root = url.standardizedFileURL
        let top = root.lastPathComponent
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        guard let walker = fileManager.enumerator(at: root, includingPropertiesForKeys: keys) else {
            throw Failure("Couldn't read \(top)")
        }
        var files: [MacDropFile] = []
        while let entry = walker.nextObject() as? URL {
            guard !skipped.contains(entry.lastPathComponent) else { continue }
            let entryValues = try? entry.resourceValues(forKeys: Set(keys))
            guard entryValues?.isSymbolicLink != true, entryValues?.isRegularFile == true else { continue }
            let entryPath = entry.standardizedFileURL.path
            guard entryPath.hasPrefix(root.path + "/") else { continue }
            guard files.count < maxFiles else { throw tooMany }
            let relative = entryPath.dropFirst(root.path.count + 1)
            files.append(file(entry, path: "\(top)/\(relative)", size: entryValues?.fileSize ?? 0))
        }
        guard !files.isEmpty else { throw Failure("\(top) is empty") }
        return Item(url: url, files: files)
    }

    static func expand(_ urls: [URL]) throws -> [Item] {
        let items = try urls.map(expand)
        guard items.reduce(0, { $0 + $1.files.count }) <= maxFiles else { throw tooMany }
        return items
    }

    static let tooMany = Failure("Vitals sends up to 10,000 files at once")

    private static func file(_ url: URL, path: String?, size: Int) -> MacDropFile {
        MacDropFile(
            name: url.lastPathComponent,
            path: path,
            size: size,
            mime: UTType(filenameExtension: url.pathExtension)?.preferredMIMEType,
            origin: url.standardizedFileURL.path
        )
    }

    static func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] ?? []
        var seen = Set<String>()
        return urls.filter { $0.isFileURL && seen.insert($0.standardizedFileURL.path).inserted }
    }

    static func stagedURL(_ stored: String, in staging: URL) -> URL? {
        guard stored.wholeMatch(of: #/[A-Za-z0-9-]{8,64}\/[A-Za-z0-9-]{1,64}/#) != nil else { return nil }
        let url = staging.appendingPathComponent(stored).standardizedFileURL
        return url.path.hasPrefix(staging.standardizedFileURL.path + "/") ? url : nil
    }

    static func components(of file: ReceivedDropFile) -> [String] {
        let leaf = file.path.flatMap { $0.split(separator: "/").last.map(String.init) }
        let name = ClipDrop.sanitize(leaf) ?? ClipDrop.sanitize(file.name) ?? "File"
        let folders = (file.path ?? "").split(separator: "/").dropLast().compactMap { ClipDrop.sanitize(String($0)) }
        return folders + [name]
    }

    static func place(_ files: [ReceivedDropFile], staging: URL, into folder: URL) throws -> Placed {
        let fileManager = FileManager.default
        let base = folder.standardizedFileURL
        do {
            try fileManager.createDirectory(at: base, withIntermediateDirectories: true)
        } catch {
            throw Failure("Couldn't open \(base.lastPathComponent)")
        }
        var roots: [String: URL] = [:]
        var items: [URL] = []
        var placed = 0
        var bytes = 0
        var failed = 0
        for file in files {
            guard let source = stagedURL(file.stored, in: staging), fileManager.fileExists(atPath: source.path) else {
                failed += 1
                continue
            }
            let parts = components(of: file)
            do {
                var directory = base
                if parts.count > 1 {
                    if let root = roots[parts[0]] {
                        directory = root
                    } else {
                        directory = ClipDrop.uniqueURL(for: parts[0], in: base)
                        try fileManager.createDirectory(at: directory, withIntermediateDirectories: false)
                        ClipDrop.quarantine(directory)
                        roots[parts[0]] = directory
                        items.append(directory)
                    }
                    for part in parts.dropFirst().dropLast() {
                        directory.appendPathComponent(part, isDirectory: true)
                        if !fileManager.fileExists(atPath: directory.path) {
                            try fileManager.createDirectory(at: directory, withIntermediateDirectories: false)
                            ClipDrop.quarantine(directory)
                        }
                    }
                }
                let target = ClipDrop.uniqueURL(for: parts[parts.count - 1], in: directory).standardizedFileURL
                guard target.path.hasPrefix(base.path + "/") else { throw Failure("Escaped the receive folder") }
                try fileManager.moveItem(at: source, to: target)
                ClipDrop.quarantine(target)
                if parts.count == 1 { items.append(target) }
                placed += 1
                bytes += file.size
            } catch {
                Log.notice(.remote, "couldn't place a received file", error: error)
                failed += 1
            }
        }
        return Placed(items: items, files: placed, bytes: bytes, failed: failed)
    }

    static func appKind(_ name: String) -> AppKind? {
        switch (name as NSString).pathExtension.lowercased() {
        case "dmg", "pkg", "mpkg", "app": return .mac
        case "apk", "apks", "xapk": return .android
        default: return nil
        }
    }

    static func topLevelNames(_ files: [(name: String, path: String?)]) -> [String] {
        var seen = Set<String>()
        return files.compactMap { file in
            let top = file.path.flatMap { $0.split(separator: "/").first.map(String.init) } ?? file.name
            return seen.insert(top).inserted ? top : nil
        }
    }

    static func label(_ names: [String]) -> String {
        switch names.count {
        case 0: return "Nothing"
        case 1: return names[0]
        default: return "\(names[0]) and \(names.count - 1) more"
        }
    }
}

enum ShareFormat {
    static func size(_ bytes: Int) -> String {
        let value = Double(bytes)
        if value >= 1e9 { return String(format: "%.1f GB", value / 1e9) }
        if value >= 1e6 { return String(format: "%.1f MB", value / 1e6) }
        if value >= 1e3 { return "\(Int((value / 1e3).rounded())) KB" }
        return "\(bytes) bytes"
    }

    static func progress(_ done: Int, of total: Int) -> String {
        let (unit, suffix) = Double(total) >= 1e9 ? (1e9, "GB") : (1e6, "MB")
        return String(format: "%.1f of %.1f %@", Double(done) / unit, Double(total) / unit, suffix)
    }

    static func files(_ count: Int) -> String { count == 1 ? "1 file" : "\(count.formatted()) files" }

    static func names(_ names: [String]) -> String {
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default: return "\(names.dropLast().joined(separator: ", ")) and \(names[names.count - 1])"
        }
    }

    static func folder(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(home + "/") else { return path.split(separator: "/").joined(separator: " › ") }
        return path.dropFirst(home.count + 1).split(separator: "/").joined(separator: " › ")
    }
}
