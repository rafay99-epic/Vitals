import ExpoModulesCore
import Photos
import UIKit
import UniformTypeIdentifiers

/// What this iPhone shares while Vitals is open: PhotoKit photos and screenshots, and folders the
/// person picked once in Files (kept as security-scoped bookmarks).
public class VitalsShareModule: Module {
  private var picker: FolderPicker?

  public func definition() -> ModuleDefinition {
    Name("VitalsShare")

    AsyncFunction("photosAccess") { () -> String in
      SharedPhotos.access()
    }

    AsyncFunction("askPhotos") { (promise: Promise) in
      PHPhotoLibrary.requestAuthorization(for: .readWrite) { _ in promise.resolve(SharedPhotos.access()) }
    }

    AsyncFunction("photos") { (kind: String, offset: Int, limit: Int) -> [String: Any] in
      SharedPhotos.page(kind: kind, offset: offset, limit: limit)
    }

    AsyncFunction("thumbnail") { (path: String, px: Int, promise: Promise) in
      Thumbnails.make(path: path, px: CGFloat(px)) { promise.resolve($0) }
    }

    AsyncFunction("exportPhoto") { (path: String, promise: Promise) in
      SharedPhotos.export(path: path) { result in
        switch result {
        case let .success(file): promise.resolve(file)
        case let .failure(error): promise.reject("ExportFailed", error.localizedDescription)
        }
      }
    }

    AsyncFunction("folders") { () -> [[String: Any]] in
      SharedFolders.all()
    }

    AsyncFunction("removeFolder") { (id: String) in
      SharedFolders.remove(id: id)
    }

    AsyncFunction("list") { (path: String) throws -> [String: Any] in
      try LocalFiles.list(path: path)
    }

    AsyncFunction("readChunk") { (path: String, offset: Double, length: Int) throws -> [String: Any] in
      try LocalFiles.readChunk(path: path, offset: offset, length: length)
    }

    AsyncFunction("pdfPages") { (path: String) throws -> [Double] in
      try PdfPages.pages(path: path)
    }

    AsyncFunction("pdfPage") { (path: String, index: Int, width: Int) throws -> String in
      try PdfPages.page(path: path, index: index, width: width)
    }

    AsyncFunction("pdfClose") {
      PdfPages.close()
    }

    AsyncFunction("pickFolder") { (role: String, promise: Promise) in
      guard let presenter = self.appContext?.utilities?.currentViewController() else {
        promise.reject("NoWindow", "Nothing to show the folder picker over")
        return
      }
      let picker = FolderPicker { url in
        self.picker = nil
        guard let url else { return promise.resolve(nil) }
        do {
          promise.resolve(try SharedFolders.add(url: url, role: role))
        } catch {
          promise.reject("PickFailed", error.localizedDescription)
        }
      }
      self.picker = picker
      let controller = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
      controller.delegate = picker
      controller.allowsMultipleSelection = false
      presenter.present(controller, animated: true)
    }.runOnQueue(.main)
  }
}
