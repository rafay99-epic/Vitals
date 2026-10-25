import AppKit
import Foundation
import QuickLookThumbnailing
import UniformTypeIdentifiers

enum FileThumbs {
    private static let concurrency = 6
    private static let quality = 0.72

    static func make(paths: [String], pixels: Int) async -> [WireThumb] {
        let side = CGFloat(max(32, min(pixels, 512)))
        var thumbs = [String: String?]()
        await withTaskGroup(of: (String, String?).self) { group in
            var next = paths.makeIterator()
            func start() {
                guard let path = next.next() else { return }
                group.addTask { (path, await jpeg(for: path, side: side)) }
            }
            for _ in 0..<concurrency { start() }
            while let (path, data) = await group.next() {
                thumbs[path] = data
                start()
            }
        }
        return paths.map { WireThumb(path: $0, jpeg: thumbs[$0] ?? nil) }
    }

    static func trash(_ paths: [String]) -> Int {
        paths.reduce(0) { count, path in
            (try? FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)) == nil ? count : count + 1
        }
    }

    static func opensDirectly(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.contentTypeKey, .isDirectoryKey, .isPackageKey])
        if values?.isPackage == true { return false }
        if values?.isDirectory == true { return true }
        guard let type = values?.contentType, !FileManager.default.isExecutableFile(atPath: url.path) else { return false }
        if [UTType.executable, .script, .application, .package, .bundle, .unixExecutable].contains(where: type.conforms) { return false }
        return [UTType.image, .audiovisualContent, .pdf, .text, .presentation, .spreadsheet, .archive].contains(where: type.conforms)
    }

    static func show(_ path: String) {
        let url = URL(fileURLWithPath: path)
        if opensDirectly(url) { NSWorkspace.shared.open(url) } else { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }

    private static func jpeg(for path: String, side: CGFloat) async -> String? {
        let request = QLThumbnailGenerator.Request(
            fileAt: URL(fileURLWithPath: path),
            size: CGSize(width: side, height: side),
            scale: 1,
            representationTypes: .thumbnail
        )
        guard let thumbnail = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else { return nil }
        let bitmap = NSBitmapImageRep(cgImage: thumbnail.cgImage)
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: quality])?.base64EncodedString()
    }
}
