import CryptoKit
import ExpoModulesCore
import QuickLook
import Tailnet
import UIKit

public class VitalsDropModule: Module {
  private var preview: DropPreview?

  public func definition() -> ModuleDefinition {
    Name("VitalsDrop")

    Events("transfer")

    Constant("canInstallApps") { false }

    OnCreate {
      DropCenter.shared.emit = { body in self.sendEvent("transfer", body) }
    }

    OnDestroy {
      DropCenter.shared.emit = nil
    }

    AsyncFunction("upload") { (json: String) throws in
      try DropCenter.shared.upload(json)
    }

    AsyncFunction("download") { (json: String) throws in
      try DropCenter.shared.download(json)
    }

    AsyncFunction("cancel") { (job: String) in
      TailnetDropCancel(job)
    }

    AsyncFunction("installApk") { (_: String) throws in
      throw Exception(name: "Unsupported", description: "Apps can't be installed on iOS")
    }

    AsyncFunction("openFile") { (uri: String, _: String?) throws in
      guard let url = URL(string: uri), url.isFileURL else {
        throw Exception(name: "BadUri", description: "Not a file")
      }
      guard let presenter = self.appContext?.utilities?.currentViewController() else {
        throw Exception(name: "NoWindow", description: "Nothing to show the file over")
      }
      let preview = DropPreview(url: url)
      self.preview = preview
      let controller = QLPreviewController()
      controller.dataSource = preview
      presenter.present(controller, animated: true)
    }.runOnQueue(.main)
  }
}

final class DropPreview: NSObject, QLPreviewControllerDataSource {
  let url: URL

  init(url: URL) {
    self.url = url
  }

  func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

  func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { url as NSURL }
}

final class DropCenter: NSObject, TailnetDropListenerProtocol, @unchecked Sendable {
  static let shared = DropCenter()

  private struct Active {
    let partial: URL?
    let name: String
    let path: String?
  }

  private let lock = NSLock()
  private var jobs: [String: Active] = [:]
  private var task: UIBackgroundTaskIdentifier = .invalid
  var emit: (([String: Any?]) -> Void)?

  override init() {
    super.init()
    NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
      guard let self, !self.idle() else { return }
      self.keepAlive()
    }
  }

  func upload(_ json: String) throws {
    let config = try parse(json)
    guard let uri = config["uri"] as? String, let url = URL(string: uri), url.isFileURL else {
      throw Exception(name: "BadUri", description: "Not a file")
    }
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    let fd = open(url.path, O_RDONLY)
    guard fd >= 0 else { throw Exception(name: "Unreadable", description: "Can't open the file") }
    try start(config, Active(partial: nil, name: "", path: nil), json, fd, TailnetDropUpload)
  }

  func download(_ json: String) throws {
    let config = try parse(json)
    guard let job = config["job"] as? String, let name = config["name"] as? String else {
      throw Exception(name: "BadJob", description: "Bad transfer job")
    }
    let dir = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
      .appendingPathComponent("drop-partial", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let digest = SHA256.hash(data: Data(job.utf8)).map { String(format: "%02x", $0) }.joined()
    let partial = dir.appendingPathComponent(digest)
    let fd = open(partial.path, O_RDWR | O_CREAT, 0o644)
    guard fd >= 0 else { throw Exception(name: "Unwritable", description: "Can't save the file") }
    try start(config, Active(partial: partial, name: name, path: config["path"] as? String), json, fd, TailnetDropDownload)
  }

  private func parse(_ json: String) throws -> [String: Any] {
    guard let config = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else {
      throw Exception(name: "BadJob", description: "Bad transfer job")
    }
    return config
  }

  private func start(
    _ config: [String: Any],
    _ active: Active,
    _ json: String,
    _ fd: Int32,
    _ run: (String?, String?, Int, (any TailnetDropListenerProtocol)?, NSErrorPointer) -> Bool
  ) throws {
    guard let job = config["job"] as? String else {
      close(fd)
      throw Exception(name: "BadJob", description: "Bad transfer job")
    }
    lock.lock()
    let busy = jobs[job] != nil
    if !busy { jobs[job] = active }
    lock.unlock()
    if busy {
      close(fd)
      throw Exception(name: "Busy", description: "already running")
    }
    keepAlive()
    var error: NSError?
    _ = run(job, json, Int(fd), self, &error)
    if let error {
      _ = remove(job)
      settle()
      throw error
    }
  }

  private func remove(_ job: String) -> Active? {
    lock.lock()
    defer { lock.unlock() }
    return jobs.removeValue(forKey: job)
  }

  private func idle() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return jobs.isEmpty
  }

  func onProgress(_ job: String?, done: Int64, total: Int64, route: String?) {
    emit?(["type": "progress", "job": job, "done": Double(done), "total": Double(total), "route": route])
  }

  func onDone(_ job: String?, sha256: String?) {
    guard let job else { return }
    let active = remove(job)
    var uri: String?
    if let active, let partial = active.partial {
      do {
        uri = try place(partial, active).absoluteString
      } catch {
        try? FileManager.default.removeItem(at: partial)
        emit?(["type": "error", "job": job, "message": "Can't save the file", "retryable": false])
        return settle()
      }
    }
    emit?(["type": "done", "job": job, "sha256": sha256, "uri": uri])
    settle()
  }

  func onError(_ job: String?, message: String?, retryable: Bool) {
    guard let job else { return }
    if !retryable, let partial = remove(job)?.partial, message == "Cancelled" {
      try? FileManager.default.removeItem(at: partial)
    }
    emit?(["type": "error", "job": job, "message": message, "retryable": retryable])
    if !retryable { settle() }
  }

  private func place(_ partial: URL, _ active: Active) throws -> URL {
    let files = FileManager.default
    let parts = (active.path ?? "").split(separator: "/").map(String.init).filter { $0 != "." && $0 != ".." && !$0.isEmpty }
    let root = try files.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("Vitals", isDirectory: true)
    let dir = parts.reduce(root) { $0.appendingPathComponent($1, isDirectory: true) }
    try files.createDirectory(at: dir, withIntermediateDirectories: true)
    let name = active.name.replacingOccurrences(of: "/", with: "_")
    let stem = (name as NSString).deletingPathExtension
    let ext = (name as NSString).pathExtension
    var target = dir.appendingPathComponent(name)
    var n = 1
    while files.fileExists(atPath: target.path) {
      n += 1
      target = dir.appendingPathComponent(ext.isEmpty ? "\(stem) (\(n))" : "\(stem) (\(n)).\(ext)")
    }
    try files.moveItem(at: partial, to: target)
    return target
  }

  private func keepAlive() {
    DispatchQueue.main.async {
      guard self.task == .invalid else { return }
      self.task = UIApplication.shared.beginBackgroundTask(withName: "Vitals transfer") { self.expire() }
    }
  }

  private func expire() {
    lock.lock()
    let running = Array(jobs.keys)
    lock.unlock()
    running.forEach { emit?(["type": "error", "job": $0, "message": "Paused. Open Vitals to finish.", "retryable": true]) }
    end()
  }

  private func settle() {
    DispatchQueue.main.async {
      if self.idle() { self.end() }
    }
  }

  private func end() {
    guard task != .invalid else { return }
    UIApplication.shared.endBackgroundTask(task)
    task = .invalid
  }
}
