import Foundation
import SwiftUI

/// State for the Cleanup tab: category sizes and the clean operation.
@MainActor
final class CleanupModel: ObservableObject {
    @Published private(set) var categories: [CleanupCategory] = []
    @Published private(set) var isScanning = false
    @Published private(set) var isCleaning = false
    @Published var selected: Set<CleanupCategory.Kind> = []
    @Published private(set) var lastResult: DiskCleaner.CleanResult?

    var selectedBytes: UInt64 {
        categories.filter { selected.contains($0.kind) }.reduce(0) { $0 + $1.sizeBytes }
    }

    var totalBytes: UInt64 {
        categories.reduce(0) { $0 + $1.sizeBytes }
    }

    func refresh() {
        guard !isScanning else { return }
        isScanning = true
        Task {
            var scanned = await Task.detached(priority: .userInitiated) { DiskCleaner.scan() }.value
            categories = scanned  // show structure immediately, sizes follow
            for index in scanned.indices {
                let category = scanned[index]
                let size = await Task.detached(priority: .utility) { DiskCleaner.size(of: category) }.value
                scanned[index].sizeBytes = size
                categories = scanned
            }
            isScanning = false
        }
    }

    func clean() {
        let targets = categories.filter { selected.contains($0.kind) && $0.sizeBytes > 0 }
        guard !targets.isEmpty, !isCleaning else { return }
        isCleaning = true
        Task {
            lastResult = await Task.detached(priority: .userInitiated) { DiskCleaner.clean(targets) }.value
            isCleaning = false
            selected.removeAll()
            refresh()
        }
    }

    func dismissResult() {
        lastResult = nil
    }
}
