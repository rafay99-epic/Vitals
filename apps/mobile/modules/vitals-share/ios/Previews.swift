import Foundation
import PDFKit
import UIKit

/// Folder listings and file reads for other devices browsing this iPhone, off the JS thread.
enum LocalFiles {
  /// Every visible entry of `path` in one call, as parallel arrays.
  static func list(path: String) throws -> [String: Any] {
    let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
    let urls = try FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: path, isDirectory: true), includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
    var names: [String] = []
    var dirs: [Bool] = []
    var sizes: [Double] = []
    var times: [Double] = []
    names.reserveCapacity(urls.count)
    for url in urls {
      let values = try? url.resourceValues(forKeys: Set(keys))
      let folder = values?.isDirectory ?? false
      names.append(url.lastPathComponent)
      dirs.append(folder)
      sizes.append(folder ? 0 : Double(values?.fileSize ?? 0))
      times.append(((values?.contentModificationDate ?? Date(timeIntervalSince1970: 0)).timeIntervalSince1970 * 1000).rounded())
    }
    return ["names": names, "dirs": dirs, "sizes": sizes, "times": times]
  }

  /// Up to `length` bytes of `path` from `offset`, as base64, with how many were read and the file's size.
  static func readChunk(path: String, offset: Double, length: Int) throws -> [String: Any] {
    let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
    defer { try? handle.close() }
    let total = try handle.seekToEnd()
    let start = min(UInt64(max(0, offset)), total)
    try handle.seek(toOffset: start)
    let data = try handle.read(upToCount: length) ?? Data()
    return ["data": data.base64EncodedString(), "read": data.count, "total": Double(total)]
  }
}

/// PDF pages for the preview screen, through PDFKit. One document stays open; calls are serialized.
enum PdfPages {
  private static let lock = NSLock()
  private static var open: (path: String, document: PDFDocument)?
  /// A tall page is drawn narrower rather than as a huge bitmap.
  private static let maxPixels = 12_000_000.0

  private static func document(path: String) throws -> PDFDocument {
    if let open, open.path == path { return open.document }
    guard let document = PDFDocument(url: URL(fileURLWithPath: path)) else {
      throw NSError(domain: "VitalsShare", code: 2, userInfo: [NSLocalizedDescriptionKey: "Can't read this PDF"])
    }
    if document.isLocked {
      throw NSError(domain: "VitalsShare", code: 3, userInfo: [NSLocalizedDescriptionKey: "This PDF has a password"])
    }
    open = (path, document)
    return document
  }

  private static func bounds(of page: PDFPage) -> CGSize {
    let box = page.bounds(for: .mediaBox).size
    return page.rotation % 180 == 0 ? box : CGSize(width: box.height, height: box.width)
  }

  /// Each page's height over its width, in order. Its length is the page count.
  static func pages(path: String) throws -> [Double] {
    lock.lock()
    defer { lock.unlock() }
    let document = try document(path: path)
    return (0 ..< document.pageCount).map { index in
      guard let page = document.page(at: index) else { return 1.414 }
      let size = bounds(of: page)
      return Double(size.height / max(size.width, 1))
    }
  }

  /// Page `index` drawn `width` pixels wide on white, as a PNG in the caches folder. Drawn once per document, page and width.
  static func page(path: String, index: Int, width: Int) throws -> String {
    lock.lock()
    defer { lock.unlock() }
    let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("vitals-pdf", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let modified = ((try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date) ?? Date(timeIntervalSince1970: 0)).timeIntervalSince1970
    let out = folder.appendingPathComponent("\(String(UInt(bitPattern: path.hashValue), radix: 16))-\(Int(modified))-\(index)-\(width).png")
    if FileManager.default.fileExists(atPath: out.path) { return out.absoluteString }
    let document = try document(path: path)
    guard let page = document.page(at: index) else {
      throw NSError(domain: "VitalsShare", code: 4, userInfo: [NSLocalizedDescriptionKey: "No page \(index + 1)"])
    }
    let size = bounds(of: page)
    let aspect = Double(size.height / max(size.width, 1))
    let wide = max(1, min(Double(width), (maxPixels / aspect).squareRoot()))
    let pixels = CGSize(width: wide.rounded(), height: max(1, (wide * aspect).rounded()))
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    let image = UIGraphicsImageRenderer(size: pixels, format: format).image { context in
      UIColor.white.setFill()
      context.fill(CGRect(origin: .zero, size: pixels))
      let scale = pixels.width / max(size.width, 1)
      context.cgContext.translateBy(x: 0, y: pixels.height)
      context.cgContext.scaleBy(x: scale, y: -scale)
      page.draw(with: .mediaBox, to: context.cgContext)
    }
    guard let png = image.pngData() else {
      throw NSError(domain: "VitalsShare", code: 5, userInfo: [NSLocalizedDescriptionKey: "Couldn't draw page \(index + 1)"])
    }
    try png.write(to: out, options: .atomic)
    return out.absoluteString
  }

  static func close() {
    lock.lock()
    defer { lock.unlock() }
    open = nil
  }
}
