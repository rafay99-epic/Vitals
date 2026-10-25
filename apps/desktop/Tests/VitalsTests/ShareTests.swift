import AppKit
import Carbon.HIToolbox
import Foundation
import Testing
@testable import Vitals

private func tempDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("vitals-share-tests-\(UUID().uuidString)", isDirectory: true)
        .resolvingSymlinksInPath()
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func write(_ text: String, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
}

private func json(_ message: FromApp) throws -> NSDictionary {
    try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(message)) as? NSDictionary)
}

private func object(_ text: String) throws -> NSDictionary {
    try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? NSDictionary)
}

struct DropBridgeTests {
    private let dropLine = #"""
    {"t":"drop","drop":{"id":"drop-0001","from":{"_tag":"Device","deviceId":"dev-1","name":"Pixel 9 Pro"},"to":{"_tag":"Mac","name":"Mac Studio"},
    "files":[{"id":"f1","name":"a.jpg","path":"Trip/day 1/a.jpg","size":10,"mime":"image/jpeg","sha256":null,"done":4},
    {"id":"f2","name":"b.txt","path":null,"size":5,"mime":null,"sha256":null,"done":0}],
    "bytes":15,"done":4,"state":"running","route":"lan","createdAt":1790000000000,"updatedAt":1790000001000,"error":null}}
    """#

    @Test func gatewayDropMessagesDecode() throws {
        let message = try JSONDecoder().decode(ToApp.self, from: Data(dropLine.utf8))
        guard case let .drop(drop) = message else { Issue.record("not a drop"); return }
        #expect(drop.id == "drop-0001")
        #expect(drop.from == .device(id: "dev-1", name: "Pixel 9 Pro"))
        #expect(drop.to == .mac(name: "Mac Studio"))
        #expect(!drop.isOutgoing && drop.phone.name == "Pixel 9 Pro")
        #expect(drop.state == .running && drop.route == .lan && drop.error == nil)
        #expect(drop.files[0].path == "Trip/day 1/a.jpg" && drop.files[1].path == nil)
        #expect(drop.percent == 26)

        let removed = try JSONDecoder().decode(ToApp.self, from: Data(#"{"t":"dropRemoved","id":"drop-0001"}"#.utf8))
        #expect(removed == .dropRemoved(id: "drop-0001"))

        let received = try JSONDecoder().decode(ToApp.self, from: Data(#"""
        {"t":"dropReceived","id":"drop-0001","from":{"_tag":"Device","deviceId":"dev-1","name":"Pixel 9 Pro"},
        "files":[{"stored":"drop-0001/f1","name":"a.jpg","path":"Trip/day 1/a.jpg","size":10},{"stored":"drop-0001/f2","name":"b.txt","path":null,"size":5}]}
        """#.utf8))
        #expect(received == .dropReceived(id: "drop-0001", from: .device(id: "dev-1", name: "Pixel 9 Pro"), files: [
            ReceivedDropFile(stored: "drop-0001/f1", name: "a.jpg", path: "Trip/day 1/a.jpg", size: 10),
            ReceivedDropFile(stored: "drop-0001/f2", name: "b.txt", path: nil, size: 5)
        ], dest: nil))
    }

    @Test func appDropMessagesMatchTheContract() throws {
        let send = FromApp.dropSend(to: ["dev-1"], files: [
            MacDropFile(name: "a.jpg", path: "Trip/a.jpg", size: 10, mime: "image/jpeg", origin: "/Users/me/Trip/a.jpg"),
            MacDropFile(name: "b", path: nil, size: 0, mime: nil, origin: "/Users/me/b")
        ])
        #expect(try json(send) == object(#"""
        {"t":"dropSend","to":["dev-1"],"files":[{"name":"a.jpg","path":"Trip/a.jpg","size":10,"mime":"image/jpeg","origin":"/Users/me/Trip/a.jpg"},
        {"name":"b","path":null,"size":0,"mime":null,"origin":"/Users/me/b"}]}
        """#))
        #expect(try json(.dropDecision(id: "drop-0001", accept: true)) == object(#"{"t":"dropDecision","id":"drop-0001","accept":true}"#))
        #expect(try json(.dropCancel(id: "drop-0001")) == object(#"{"t":"dropCancel","id":"drop-0001"}"#))
        #expect(try json(.dropPause(id: "drop-0001", paused: false)) == object(#"{"t":"dropPause","id":"drop-0001","paused":false}"#))
        #expect(try json(.dropPolicy(DropPolicy(autoAccept: true, askWeb: false, maxBytes: 50_000_000_000)))
            == object(#"{"t":"dropPolicy","policy":{"autoAccept":true,"askWeb":false,"maxBytes":50000000000}}"#))
    }

    @Test func pushedClipsSayPushedAndOthersLeaveItOut() throws {
        let pushed = try json(.clip(MacClip(id: "clip-0001", kind: .text, at: 1, source: nil, text: "hi", pushed: true)))
        #expect((pushed["clip"] as? NSDictionary)?["pushed"] as? Bool == true)
        let copied = try json(.clip(MacClip(id: "clip-0002", kind: .text, at: 1, source: nil, text: "hi")))
        #expect((copied["clip"] as? NSDictionary)?["pushed"] == nil)
    }

    @Test func shareNotificationActionsMapBackToTheDrop() {
        let ask = NotificationManager.shareNotificationId(NotificationManager.Category.shareAsk, "drop-0001")
        let got = NotificationManager.shareNotificationId(NotificationManager.Category.shareGot, "drop-0001")
        let wait = NotificationManager.shareNotificationId(NotificationManager.Category.shareWait, "drop-0001")
        #expect(NotificationManager.shareAction(NotificationManager.Action.acceptDrop, identifier: ask) == .decide("drop-0001", accept: true))
        #expect(NotificationManager.shareAction(NotificationManager.Action.declineDrop, identifier: ask) == .decide("drop-0001", accept: false))
        #expect(NotificationManager.shareAction(NotificationManager.Action.showDrop, identifier: got) == .show("drop-0001"))
        #expect(NotificationManager.shareAction(NotificationManager.Action.cancelDrop, identifier: wait) == .cancel("drop-0001"))
        #expect(NotificationManager.shareAction(NotificationManager.Action.acceptDrop, identifier: got) == nil)
    }
}

struct DropSendTests {
    @Test func foldersExpandIntoFilesWithRelativePaths() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("brand-assets", isDirectory: true)
        try write("logo", to: folder.appendingPathComponent("logo.svg"))
        try write("x", to: folder.appendingPathComponent("print/cmyk/card.pdf"))
        try write("junk", to: folder.appendingPathComponent(".DS_Store"))
        try write("junk", to: folder.appendingPathComponent("print/.DS_Store"))
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("link"), withDestinationURL: folder.appendingPathComponent("logo.svg"))

        let item = try DropFiles.expand(folder)
        #expect(item.isFolder)
        let paths = item.files.map { $0.path ?? "" }.sorted()
        #expect(paths == ["brand-assets/logo.svg", "brand-assets/print/cmyk/card.pdf"])
        let card = try #require(item.files.first { $0.name == "card.pdf" })
        #expect(card.size == 1 && card.mime == "application/pdf")
        #expect(card.origin == folder.appendingPathComponent("print/cmyk/card.pdf").path)
        #expect(item.bytes == 5)
    }

    @Test func aLoneFileHasNoPath() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("invoice-oct.pdf")
        try write("pdf!", to: file)
        let item = try DropFiles.expand(file)
        #expect(item.files == [MacDropFile(name: "invoice-oct.pdf", path: nil, size: 4, mime: "application/pdf", origin: file.path)])
        #expect(!item.isFolder)
        #expect(throws: DropFiles.Failure.self) { try DropFiles.expand(root.appendingPathComponent("gone.pdf")) }
    }

    @Test func emptyFoldersCantBeSent() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let empty = root.appendingPathComponent("Empty", isDirectory: true)
        try write("junk", to: empty.appendingPathComponent(".DS_Store"))
        #expect(throws: DropFiles.Failure("Empty is empty")) { try DropFiles.expand(empty) }
    }

    @Test func servicesReadEveryFileURLOnceAndNothingElse() throws {
        let board = NSPasteboard(name: NSPasteboard.Name("vitals-share-test-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        board.clearContents()
        let a = URL(fileURLWithPath: "/tmp/a.pdf")
        let folder = URL(fileURLWithPath: "/tmp/Folder", isDirectory: true)
        #expect(board.writeObjects([a as NSURL, folder as NSURL, a as NSURL, URL(string: "https://example.com")! as NSURL]))
        #expect(DropFiles.fileURLs(from: board).map(\.path) == ["/tmp/a.pdf", "/tmp/Folder"])

        board.clearContents()
        board.setString("not a file", forType: .string)
        #expect(DropFiles.fileURLs(from: board).isEmpty)
    }

    @Test func labelsNameTheTopLevelItems() {
        let names = DropFiles.topLevelNames([("a.jpg", "Trip/a.jpg"), ("b.jpg", "Trip/x/b.jpg"), ("c.pdf", nil)])
        #expect(names == ["Trip", "c.pdf"])
        #expect(DropFiles.label(names) == "Trip and 1 more")
        #expect(DropFiles.label(["c.pdf"]) == "c.pdf")
        #expect(ShareFormat.progress(500_000_000, of: 1_400_000_000) == "0.5 of 1.4 GB")
        #expect(ShareFormat.progress(1_000_000, of: 8_600_000) == "1.0 of 8.6 MB")
        #expect(ShareFormat.size(61_400_000) == "61.4 MB")
        #expect(ShareFormat.names(["Pixel 9 Pro", "iPhone 17"]) == "Pixel 9 Pro and iPhone 17")
    }
}

struct DropReceiveTests {
    private func stage(_ files: [(stored: String, text: String)], in staging: URL) throws {
        for file in files { try write(file.text, to: staging.appendingPathComponent(file.stored)) }
    }

    @Test func foldersAreRecreatedAndEverythingIsQuarantined() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let staging = root.appendingPathComponent("drop")
        let inbox = root.appendingPathComponent("Downloads/Vitals")
        try stage([("drop-0001/f1", "a"), ("drop-0001/f2", "bb"), ("drop-0001/f3", "c")], in: staging)
        let placed = try DropFiles.place([
            ReceivedDropFile(stored: "drop-0001/f1", name: "a.jpg", path: "Trip/day 1/a.jpg", size: 1),
            ReceivedDropFile(stored: "drop-0001/f2", name: "b.jpg", path: "Trip/b.jpg", size: 2),
            ReceivedDropFile(stored: "drop-0001/f3", name: "notes.txt", path: nil, size: 1)
        ], staging: staging, into: inbox)

        #expect(placed.files == 3 && placed.failed == 0 && placed.bytes == 4)
        #expect(placed.items.map(\.lastPathComponent) == ["Trip", "notes.txt"])
        #expect(try String(contentsOf: inbox.appendingPathComponent("Trip/day 1/a.jpg"), encoding: .utf8) == "a")
        #expect(try String(contentsOf: inbox.appendingPathComponent("Trip/b.jpg"), encoding: .utf8) == "bb")
        #expect(!FileManager.default.fileExists(atPath: staging.appendingPathComponent("drop-0001/f1").path))
        for path in ["Trip", "Trip/day 1", "Trip/day 1/a.jpg", "notes.txt"] {
            #expect(getxattr(inbox.appendingPathComponent(path).path, "com.apple.quarantine", nil, 0, 0, 0) > 0, "\(path) quarantined")
        }
    }

    @Test func nothingIsOverwrittenAndRepeatsGetNumbered() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let staging = root.appendingPathComponent("drop")
        let inbox = root.appendingPathComponent("Inbox")
        try write("old", to: inbox.appendingPathComponent("notes.txt"))
        try write("old", to: inbox.appendingPathComponent("Trip/a.jpg"))
        try stage([("drop-0002/f1", "new"), ("drop-0002/f2", "new a"), ("drop-0002/f3", "second")], in: staging)
        let placed = try DropFiles.place([
            ReceivedDropFile(stored: "drop-0002/f1", name: "notes.txt", path: nil, size: 3),
            ReceivedDropFile(stored: "drop-0002/f2", name: "a.jpg", path: "Trip/a.jpg", size: 5),
            ReceivedDropFile(stored: "drop-0002/f3", name: "a.jpg", path: "Trip/a.jpg", size: 6)
        ], staging: staging, into: inbox)

        #expect(placed.items.map(\.lastPathComponent) == ["notes 2.txt", "Trip 2"])
        #expect(try String(contentsOf: inbox.appendingPathComponent("notes.txt"), encoding: .utf8) == "old")
        #expect(try String(contentsOf: inbox.appendingPathComponent("Trip/a.jpg"), encoding: .utf8) == "old")
        #expect(try String(contentsOf: inbox.appendingPathComponent("Trip 2/a.jpg"), encoding: .utf8) == "new a")
        #expect(try String(contentsOf: inbox.appendingPathComponent("Trip 2/a 2.jpg"), encoding: .utf8) == "second")
    }

    @Test func pathsNeverEscapeTheFolder() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let staging = root.appendingPathComponent("drop")
        let inbox = root.appendingPathComponent("Inbox")
        try stage([("drop-0003/f1", "1"), ("drop-0003/f2", "2"), ("drop-0003/f3", "3")], in: staging)
        try write("secret", to: root.appendingPathComponent("secret"))
        let placed = try DropFiles.place([
            ReceivedDropFile(stored: "drop-0003/f1", name: "evil", path: "../../evil", size: 1),
            ReceivedDropFile(stored: "drop-0003/f2", name: "..", path: "/etc/../passwd", size: 1),
            ReceivedDropFile(stored: "drop-0003/f3", name: "x:y", path: "a/./b\\c/x:y", size: 1),
            ReceivedDropFile(stored: "../secret", name: "secret", path: nil, size: 6),
            ReceivedDropFile(stored: "drop-0003/../../secret", name: "secret", path: nil, size: 6)
        ], staging: staging, into: inbox)

        #expect(placed.files == 3 && placed.failed == 2)
        let made = try FileManager.default.subpathsOfDirectory(atPath: inbox.path).sorted()
        #expect(made == ["a", "a/b-c", "a/b-c/x-y", "etc", "etc/passwd", "evil"])
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("secret").path))
        #expect(DropFiles.stagedURL("drop-0003/f1", in: staging) != nil)
        #expect(DropFiles.stagedURL("drop-0003/../f1", in: staging) == nil)
        #expect(DropFiles.stagedURL("short/f1", in: staging) == nil)
    }

    @Test func appsAreTaggedAndApksAreNot() {
        #expect(DropFiles.appKind("Vitals-Nightly.dmg") == .mac)
        #expect(DropFiles.appKind("Installer.PKG") == .mac)
        #expect(DropFiles.appKind("Tool.app") == .mac)
        #expect(DropFiles.appKind("vitals-dev.apk") == .android)
        #expect(DropFiles.appKind("IMG_2041.HEIC") == nil)
    }
}

struct ShareSettingsTests {
    @MainActor @Test func policyDefaultsToAutoAcceptAskWebAnd50GB() throws {
        let suite = "vitals-share-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        #expect(ShareModel.policy(settings) == DropPolicy(autoAccept: true, askWeb: true, maxBytes: 50_000_000_000))
        #expect(settings.shareFolder.isEmpty)
        #expect(ShareModel.defaultFolder.path.hasSuffix("/Downloads/Vitals"))
        #expect(settings.clipShortcut == .sendClipboard)
        settings.shareMaxGB = 200
        settings.clipShortcut = nil
        let reloaded = AppSettings(defaults: defaults)
        #expect(ShareModel.policy(reloaded).maxBytes == 200_000_000_000)
        #expect(reloaded.clipShortcut == nil)
    }

    @Test func shortcutsFormatLikeMenus() {
        #expect(Shortcut.sendClipboard.display == "⌃⌥⌘V")
        #expect(Shortcut(keyCode: kVK_ANSI_1, modifiers: cmdKey | shiftKey).display == "⇧⌘1")
        #expect(Shortcut(keyCode: kVK_F5, modifiers: optionKey).display == "⌥F5")
        #expect(Shortcut(keyCode: kVK_Space, flags: [.control, .option])?.display == "⌃⌥Space")
        #expect(Shortcut(keyCode: kVK_ANSI_V, flags: [.shift]) == nil)
        #expect(Shortcut(keyCode: kVK_ANSI_V, flags: [.command, .option, .control]) == .sendClipboard)
        #expect(Shortcut(keyCode: kVK_Escape, flags: [.command]) == nil)
    }

    @Test func phonesOpenDocumentsButOnlyRevealAnythingThatRuns() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["photo.jpg", "notes.txt", "report.pdf"] { try write("x", to: root.appendingPathComponent(name)) }
        for name in ["run.command", "run.sh", "run.terminal", "run.scpt", "Tool.app/Contents/Info.plist", "bin/tool"] {
            try write("echo hi", to: root.appendingPathComponent(name))
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.appendingPathComponent("bin/tool").path)
        for name in ["photo.jpg", "notes.txt", "report.pdf", "bin"] { #expect(FileThumbs.opensDirectly(root.appendingPathComponent(name)), "\(name)") }
        for name in ["run.command", "run.sh", "run.terminal", "run.scpt", "Tool.app", "bin/tool"] { #expect(!FileThumbs.opensDirectly(root.appendingPathComponent(name)), "\(name)") }
    }
}
