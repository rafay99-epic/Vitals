import AVFoundation
import ImageIO
import Photos
import UIKit

final class FolderPicker: NSObject, UIDocumentPickerDelegate {
  private let done: (URL?) -> Void

  init(done: @escaping (URL?) -> Void) {
    self.done = done
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    done(urls.first)
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    done(nil)
  }
}

enum SharedPhotos {
  static let prefix = "/photos/"

  static func access() -> String {
    switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
    case .authorized: return "full"
    case .limited: return "limited"
    case .notDetermined: return "ask"
    default: return "denied"
    }
  }

  private static func fetch(kind: String) -> PHFetchResult<PHAsset>? {
    let options = PHFetchOptions()
    options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
    let media = NSPredicate(format: "mediaType == %d OR mediaType == %d", PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)
    switch kind {
    case "screenshots":
      guard let album = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumScreenshots, options: nil).firstObject else { return nil }
      options.predicate = media
      return PHAsset.fetchAssets(in: album, options: options)
    case "photos":
      let notShot = NSPredicate(format: "(mediaSubtypes & %d) == 0", PHAssetMediaSubtype.photoScreenshot.rawValue)
      options.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [media, notShot])
      return PHAsset.fetchAssets(with: options)
    default:
      options.predicate = media
      return PHAsset.fetchAssets(with: options)
    }
  }

  static func asset(path: String) -> PHAsset? {
    guard path.hasPrefix(prefix) else { return nil }
    let id = String(path.dropFirst(prefix.count))
    return PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
  }

  private static func resource(of asset: PHAsset) -> PHAssetResource? {
    let resources = PHAssetResource.assetResources(for: asset)
    return resources.first { $0.type == .photo || $0.type == .video } ?? resources.first
  }

  /// One page, newest first. `kind` is photos, screenshots, or all.
  static func page(kind: String, offset: Int, limit: Int) -> [String: Any] {
    guard let result = fetch(kind: kind), offset < result.count else {
      return ["entries": [[String: Any]](), "more": false, "total": 0]
    }
    let end = min(result.count, offset + limit)
    var entries: [[String: Any]] = []
    entries.reserveCapacity(end - offset)
    result.enumerateObjects(at: IndexSet(integersIn: offset ..< end), options: []) { asset, _, _ in
      let resource = resource(of: asset)
      let size = (resource?.value(forKey: "fileSize") as? Int64) ?? 0
      let at = asset.creationDate ?? asset.modificationDate ?? Date(timeIntervalSince1970: 0)
      entries.append([
        "path": prefix + asset.localIdentifier,
        "name": resource?.originalFilename ?? (asset.mediaType == .video ? "Video.mov" : "Photo.heic"),
        "size": Double(max(0, size)),
        "modifiedAt": (at.timeIntervalSince1970 * 1000).rounded(),
      ])
    }
    return ["entries": entries, "more": end < result.count, "total": result.count]
  }

  /// Copies the original out of the library into a temp file, so it can be sent like any file.
  static func export(path: String, done: @escaping (Result<[String: Any], Error>) -> Void) {
    guard let asset = asset(path: path), let resource = resource(of: asset) else {
      return done(.failure(NSError(domain: "VitalsShare", code: 1, userInfo: [NSLocalizedDescriptionKey: "That photo is gone"])))
    }
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("vitals-photos", isDirectory: true).appendingPathComponent(UUID().uuidString, isDirectory: true)
    let file = folder.appendingPathComponent(resource.originalFilename)
    do {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    } catch {
      return done(.failure(error))
    }
    let options = PHAssetResourceRequestOptions()
    options.isNetworkAccessAllowed = true
    PHAssetResourceManager.default().writeData(for: resource, toFile: file, options: options) { error in
      if let error { return done(.failure(error)) }
      let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.doubleValue ?? 0
      done(.success(["uri": file.absoluteString, "name": resource.originalFilename, "size": size]))
    }
  }
}

enum Thumbnails {
  private static let video: Set<String> = ["mov", "mp4", "m4v", "avi", "mkv", "webm", "3gp"]

  static func make(path: String, px: CGFloat, done: @escaping (String?) -> Void) {
    if let asset = SharedPhotos.asset(path: path) {
      let options = PHImageRequestOptions()
      options.deliveryMode = .highQualityFormat
      options.resizeMode = .fast
      options.isNetworkAccessAllowed = true
      PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: px, height: px), contentMode: .aspectFill, options: options) { image, _ in
        done(image?.jpegData(compressionQuality: 0.72)?.base64EncodedString())
      }
      return
    }
    let url = URL(fileURLWithPath: path)
    if video.contains(url.pathExtension.lowercased()) {
      let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
      generator.appliesPreferredTrackTransform = true
      generator.maximumSize = CGSize(width: px, height: px)
      generator.generateCGImageAsynchronously(for: .zero) { image, _, _ in
        done(image.flatMap { UIImage(cgImage: $0).jpegData(compressionQuality: 0.72)?.base64EncodedString() })
      }
      return
    }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: px,
    ]
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
      return done(nil)
    }
    done(UIImage(cgImage: image).jpegData(compressionQuality: 0.72)?.base64EncodedString())
  }
}

/// Folders picked in Files. Each stays readable across launches through its bookmark. `role` is
/// downloads, documents, or other; picking a new Downloads or Documents folder replaces the old one.
enum SharedFolders {
  private static let key = "vitals.share.folders"
  private static var opened: [String: URL] = [:]

  private static func stored() -> [[String: Any]] {
    UserDefaults.standard.array(forKey: key) as? [[String: Any]] ?? []
  }

  private static func save(_ items: [[String: Any]]) {
    UserDefaults.standard.set(items, forKey: key)
  }

  private static func open(id: String, url: URL) {
    if opened[id] != nil { return }
    if url.startAccessingSecurityScopedResource() { opened[id] = url }
  }

  private static func close(id: String) {
    opened.removeValue(forKey: id)?.stopAccessingSecurityScopedResource()
  }

  private static func describe(id: String, role: String, url: URL) -> [String: Any] {
    ["id": id, "role": role, "name": url.lastPathComponent, "path": url.standardizedFileURL.path]
  }

  static func add(url: URL, role: String) throws -> [String: Any] {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    let id = UUID().uuidString
    var items = stored()
    if role != "other" {
      for item in items where item["role"] as? String == role {
        if let old = item["id"] as? String { close(id: old) }
      }
      items.removeAll { $0["role"] as? String == role }
    }
    items.append(["id": id, "role": role, "bookmark": bookmark])
    save(items)
    open(id: id, url: url)
    return describe(id: id, role: role, url: url)
  }

  static func remove(id: String) {
    close(id: id)
    save(stored().filter { $0["id"] as? String != id })
  }

  /// Every folder that still resolves, opened for reading. Stale bookmarks are refreshed.
  static func all() -> [[String: Any]] {
    var items = stored()
    var out: [[String: Any]] = []
    for (index, item) in items.enumerated() {
      guard let id = item["id"] as? String, let role = item["role"] as? String, let data = item["bookmark"] as? Data else { continue }
      var stale = false
      guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else { continue }
      open(id: id, url: url)
      if stale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
        items[index]["bookmark"] = fresh
      }
      out.append(describe(id: id, role: role, url: url))
    }
    save(items)
    return out
  }
}
