import Testing
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import Vitals

private func tempDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("vitals-clip-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private let plainText = "public.utf8-plain-text"

struct ClipCaptureTests {
    @Test func passwordMarkersAndPasswordAppsAreNeverRecorded() {
        for marker in ClipCapture.privateTypes {
            #expect(ClipCapture.classify(PasteboardContents(types: [marker, plainText], string: "hunter2")) == nil)
        }
        for app in ClipCapture.ignoredApps {
            #expect(ClipCapture.classify(PasteboardContents(types: [plainText], frontmostBundleID: app, string: "hunter2")) == nil)
        }
        #expect(ClipCapture.classify(PasteboardContents(types: [plainText], frontmostBundleID: "com.apple.Notes", string: "hello")) == .text("hello"))
    }

    @Test func emptyAndHugeStringsAreSkipped() {
        #expect(ClipCapture.classify(PasteboardContents(string: " \n\t")) == nil)
        #expect(ClipCapture.classify(PasteboardContents(string: String(repeating: "a", count: ClipCapture.maxStringBytes + 1))) == nil)
    }

    @Test func aLoneHttpURLIsALinkEverythingElseIsText() {
        #expect(ClipCapture.classify(PasteboardContents(string: "  https://example.com/a?b=1\n")) == .link("https://example.com/a?b=1"))
        #expect(ClipCapture.classify(PasteboardContents(string: "http://localhost:3000")) == .link("http://localhost:3000"))
        #expect(ClipCapture.classify(PasteboardContents(string: "see https://example.com")) == .text("see https://example.com"))
        #expect(ClipCapture.classify(PasteboardContents(string: "ftp://example.com")) == .text("ftp://example.com"))
        #expect(ClipCapture.classify(PasteboardContents(string: "https://")) == .text("https://"))
    }

    @Test func filesBeatImagesBeatText() {
        let urls = (0..<25).map { URL(fileURLWithPath: "/tmp/f\($0)") }
        let all = PasteboardContents(fileURLs: urls, image: .png(Data([1])), string: "name")
        #expect(ClipCapture.classify(all) == .files(Array(urls.prefix(ClipCapture.maxFiles))))
        #expect(ClipCapture.classify(PasteboardContents(image: .png(Data([1])), string: "x")) == .image(.png(Data([1]))))
    }

    @Test func richTextCopiesWithAPictureStayText() {
        let office = PasteboardContents(types: ["public.rtf", plainText, "public.png"])
        #expect(ClipCapture.prefersText(office))
        #expect(!ClipCapture.prefersText(PasteboardContents(types: ["public.html", "public.png"])))
    }

    @Test func longTextIsStoredWithAPreview() throws {
        let directory = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let long = String(repeating: "x", count: ClipCapture.inlineTextBytes + 1)
        let clip = try #require(ClipCapture.clips(for: .text(long), at: 1, source: "Notes", directory: directory).first)
        #expect(clip.truncated)
        #expect(clip.text?.count == ClipCapture.previewCharacters)
        #expect(clip.stored == "\(clip.id).txt")
        #expect(clip.bytes == long.utf8.count)
        #expect(clip.id.wholeMatch(of: #/[a-z0-9-]{8,64}/#) != nil)
        #expect(try String(contentsOf: directory.appendingPathComponent(clip.stored ?? ""), encoding: .utf8) == long)

        let short = try #require(ClipCapture.clips(for: .text("hi"), at: 1, source: nil, directory: directory).first)
        #expect(!short.truncated && short.stored == nil && short.text == "hi" && short.bytes == 0)
    }

    @Test func tiffBecomesAStoredPNGWithASmallThumbnail() throws {
        let directory = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let context = try #require(CGContext(data: nil, width: 1200, height: 800, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 600, height: 800))
        let image = try #require(context.makeImage())
        let tiff = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(tiff, UTType.tiff.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))

        let clip = try #require(ClipCapture.clips(for: .image(.tiff(tiff as Data)), at: 1, source: nil, directory: directory).first)
        #expect(clip.kind == .image && clip.mime == "image/png" && clip.stored == "\(clip.id).png")
        let stored = try Data(contentsOf: directory.appendingPathComponent(clip.stored ?? ""))
        #expect(stored.count == clip.bytes)
        #expect(stored.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]))
        let thumb = try #require(clip.thumb)
        #expect(thumb.count <= ClipCapture.thumbChars)
    }
}

struct ClipDropTests {
    private let clips = URL(fileURLWithPath: "/tmp/vitals/remote/clips")

    @Test func storedNamesMustBeBareFilesInsideClips() {
        let id = UUID().uuidString.lowercased()
        for bad in ["../x", "/etc/passwd", "a/b.png", "../\(id).png", "\(id)/../x.png", "short.png", "\(id)", "\(id).PNG", "\(id).a.b.c", ""] {
            #expect(ClipDrop.storedURL(bad, in: clips) == nil, "accepted \(bad)")
        }
        #expect(ClipDrop.storedURL("\(id).png", in: clips)?.path == "/tmp/vitals/remote/clips/\(id).png")
        #expect(ClipDrop.storedURL("\(id).tar.gz", in: clips) != nil)
    }

    @Test func oneBadNameFailsTheWholeBatch() {
        let items = [
            ClipPlacement(kind: .text, stored: nil, text: "fine", name: nil, mime: nil),
            ClipPlacement(kind: .file, stored: "../../etc/passwd", text: nil, name: "passwd", mime: nil)
        ]
        #expect(throws: ClipDrop.Failure("A clip had an invalid file name")) { try ClipDrop.resolve(items, in: clips) }
    }

    @Test func downloadsNeverOverwrite() {
        let folder = URL(fileURLWithPath: "/Users/me/Downloads")
        let taken: Set<String> = ["photo.png", "photo 2.png", "notes"]
        let exists = { (url: URL) in taken.contains(url.lastPathComponent) }
        #expect(ClipDrop.uniqueURL(for: "photo.png", in: folder, exists: exists).lastPathComponent == "photo 3.png")
        #expect(ClipDrop.uniqueURL(for: "notes", in: folder, exists: exists).lastPathComponent == "notes 2")
        #expect(ClipDrop.uniqueURL(for: "new.pdf", in: folder, exists: exists).lastPathComponent == "new.pdf")
    }

    @Test func savedFilesFromPhonesAreQuarantined() throws {
        let folder = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let saved = try ClipDrop.save([.text("hi", kind: .text, name: "note")], to: folder, folder: "Pixel", deviceName: "Pixel 9 Pro")
        #expect(saved.map(\.lastPathComponent) == ["note.txt"])
        #expect(getxattr(saved[0].path, "com.apple.quarantine", nil, 0, 0, 0) > 0)
    }

    @Test func namesAreSanitizedToOnePathComponent() {
        #expect(ClipDrop.sanitize("../evil") == "-evil")
        #expect(ClipDrop.sanitize("a/b:c") == "a-b-c")
        #expect(ClipDrop.sanitize("..") == nil)
        #expect(ClipDrop.sanitize("  Trip photos ") == "Trip photos")
        let text = ClipDrop.Source.text("hi", kind: .link, name: nil)
        #expect(ClipDrop.fileName(for: text, deviceName: "Pixel 9 Pro") == "Link from Pixel 9 Pro.txt")
    }

    @Test func materializeClonesAFileAndExplainsAMissingOne() throws {
        let directory = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let origin = directory.appendingPathComponent("Report.PDF")
        try Data("pdf".utf8).write(to: origin)
        let id = UUID().uuidString.lowercased()
        let made = try ClipDrop.materialize(id: id, kind: .file, origin: origin.path, into: directory.appendingPathComponent("clips"))
        #expect(made == ClipDrop.Materialized(stored: "\(id).pdf", bytes: 3, files: nil))
        #expect(throws: ClipDrop.Failure("That file is no longer on the Mac")) {
            try ClipDrop.materialize(id: id, kind: .file, origin: "/nope/gone.txt", into: directory)
        }
    }

    @Test func statsLineIsNumericAndHonestWhenEmpty() {
        #expect(ClipboardCard.statsLine(ClipStats(clips: 0, pinned: 0, bytes: 0)) == "Empty")
        #expect(ClipboardCard.statsLine(ClipStats(clips: 2, pinned: 0, bytes: 0)) == "Using 0 bytes for 2 clips")
        #expect(ClipboardCard.statsLine(ClipStats(clips: 148, pinned: 6, bytes: 212_000_000)) == "Using 212 MB for 148 clips · 6 pinned")
    }

    @Test func summariesReadPlainly() {
        let photos = ClipDrop.summary([.image, .image], to: .clipboard, folder: nil, deviceName: "Pixel 9 Pro")
        #expect(photos.title == "Got 2 photos from Pixel 9 Pro" && photos.body == "They're on your clipboard.")
        let files = ClipDrop.summary([.file, .file, .file], to: .downloads, folder: "Trip", deviceName: "Pixel 9 Pro")
        #expect(files.title == "Saved 3 files from Pixel 9 Pro" && files.body == "They're in Downloads/Trip.")
    }
}

struct ClipBridgeTests {
    private func json(_ value: some Encodable) throws -> NSDictionary {
        try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? NSDictionary)
    }

    private func dictionary(_ literal: String) throws -> NSDictionary {
        try #require(try JSONSerialization.jsonObject(with: Data(literal.utf8)) as? NSDictionary)
    }

    @Test func clipEncodesEveryMacClipFieldWithNulls() throws {
        let clip = MacClip(id: "0f8fad5b-d9cb-469f-a165-70867728950e", kind: .file, at: 1_790_000_000_000, source: "Finder",
                           name: "Report.pdf", mime: "application/pdf", bytes: 2048, origin: "/Users/me/Report.pdf")
        #expect(try json(FromApp.clip(clip)) == dictionary("""
        {"t":"clip","clip":{"id":"0f8fad5b-d9cb-469f-a165-70867728950e","kind":"file","at":1790000000000,"source":"Finder",
        "text":null,"truncated":false,"name":"Report.pdf","mime":"application/pdf","bytes":2048,"files":null,"thumb":null,
        "stored":null,"origin":"/Users/me/Report.pdf"}}
        """))
    }

    @Test func policyAndClearMatchTheContract() throws {
        #expect(try json(FromApp.clipPolicy(ClipPolicy(enabled: true, keepDays: 7))) == dictionary(#"{"t":"clipPolicy","policy":{"enabled":true,"keepDays":7}}"#))
        #expect(try json(FromApp.clipClear) == dictionary(#"{"t":"clipClear"}"#))
    }

    @Test func queryResultsMatchTheContract() throws {
        let made = FromApp.result(id: "q-1", ok: .clipMaterialize(stored: "0f8fad5b-d9cb.zip", bytes: 512, files: 14), error: nil)
        #expect(try json(made) == dictionary(#"{"t":"result","id":"q-1","ok":{"_tag":"ClipMaterialize","stored":"0f8fad5b-d9cb.zip","bytes":512,"files":14},"error":null}"#))
        let file = FromApp.result(id: "q-2", ok: .clipMaterialize(stored: "0f8fad5b-d9cb.pdf", bytes: 3, files: nil), error: nil)
        #expect(try json(file) == dictionary(#"{"t":"result","id":"q-2","ok":{"_tag":"ClipMaterialize","stored":"0f8fad5b-d9cb.pdf","bytes":3,"files":null},"error":null}"#))
        #expect(try json(FromApp.result(id: "q-3", ok: .clipPut(placed: 2), error: nil)) == dictionary(#"{"t":"result","id":"q-3","ok":{"_tag":"ClipPut","placed":2},"error":null}"#))
    }

    @Test func gatewayClipMessagesDecode() throws {
        let stats = #"{"t":"clipStats","stats":{"clips":148,"pinned":6,"bytes":212000000}}"#
        #expect(try JSONDecoder().decode(ToApp.self, from: Data(stats.utf8)) == .clipStats(ClipStats(clips: 148, pinned: 6, bytes: 212_000_000)))

        let materialize = #"{"t":"query","id":"q-1","q":{"_tag":"ClipMaterialize","id":"0f8fad5b-d9cb","kind":"folder","origin":"/Users/me/Trip"}}"#
        #expect(try JSONDecoder().decode(ToApp.self, from: Data(materialize.utf8))
            == .query(id: "q-1", query: .clipMaterialize(id: "0f8fad5b-d9cb", kind: .folder, origin: "/Users/me/Trip")))

        let put = #"{"t":"query","id":"q-2","q":{"_tag":"ClipPut","items":[{"kind":"image","stored":"0f8fad5b-d9cb.jpg","text":null,"name":"IMG_1.jpg","mime":"image/jpeg"}],"to":"downloads","folder":null,"deviceName":"Pixel 9 Pro"}}"#
        let item = ClipPlacement(kind: .image, stored: "0f8fad5b-d9cb.jpg", text: nil, name: "IMG_1.jpg", mime: "image/jpeg")
        #expect(try JSONDecoder().decode(ToApp.self, from: Data(put.utf8))
            == .query(id: "q-2", query: .clipPut(items: [item], to: .downloads, folder: nil, deviceName: "Pixel 9 Pro")))
    }
}
