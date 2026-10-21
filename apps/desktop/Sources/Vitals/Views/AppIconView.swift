import SwiftUI
import AppKit

/// Process-wide icon cache. `NSWorkspace.icon(forFile:)` hits disk and decodes
/// the image, so misses load off-main via `Task.detached`.
enum AppIconCache {
    /// The largest size any row draws an icon at is 28 pt; bake a 32 pt @2x
    /// (64 px) bitmap so it stays crisp everywhere while costing a fixed ~16 KB.
    private static let logicalSize = NSSize(width: 32, height: 32)
    private static let backingScale = 2

    private static let cache: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        // Flattening is what bounds memory: ~16 KB per icon, one per installed
        // app. `countLimit` is a soft backstop (NSCache may briefly exceed it),
        // not a hard cap; unbounded, it only evicted under memory pressure.
        cache.countLimit = 512
        return cache
    }()

    /// Instant cache check, nil on miss. `NSCache` is thread-safe.
    static func cached(for url: URL) -> NSImage? {
        cache.object(forKey: url as NSURL)
    }

    /// Synchronous icon load; call off-main. `NSWorkspace` and `NSCache` are both
    /// thread-safe, so no actor hop is needed. Caches the flattened icon.
    nonisolated static func loadIcon(for url: URL) -> NSImage {
        let icon = flatten(NSWorkspace.shared.icon(forFile: url.path))
        cache.setObject(icon, forKey: url as NSURL)
        return icon
    }

    /// `NSWorkspace.icon(forFile:)` returns a multi-representation image whose
    /// ICNS reps run up to 512×512 / 1024×1024 — setting `.size` only changes
    /// the *draw* size, so those full-res bitmaps stay resident (~100 KB–1 MB
    /// each). Redraw once into a single small bitmap and cache that instead, so
    /// a few hundred cached icons cost megabytes, not hundreds of them.
    nonisolated static func flatten(_ source: NSImage) -> NSImage {
        let pixelsWide = Int(logicalSize.width) * backingScale
        let pixelsHigh = Int(logicalSize.height) * backingScale
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsWide, pixelsHigh: pixelsHigh,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else {
            // Bitmap allocation failed — fall back to the sized original rather
            // than nothing. Rare, and still correct, just not shrunk.
            source.size = logicalSize
            return source
        }
        rep.size = logicalSize
        NSGraphicsContext.saveGraphicsState()
        if let context = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.current = context
            context.imageInterpolation = .high
            source.draw(in: NSRect(origin: .zero, size: logicalSize))
        }
        NSGraphicsContext.restoreGraphicsState()
        let icon = NSImage(size: logicalSize)
        icon.addRepresentation(rep)
        return icon
    }
}

/// An app icon that loads off-main on a cache miss, with a neutral placeholder
/// meanwhile.
struct AppIconView: View {
    let url: URL
    let size: CGFloat
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable()
            } else {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(.quaternary.opacity(0.4))
            }
        }
        .frame(width: size, height: size)
        .task(id: url) {
            if let cached = AppIconCache.cached(for: url) {
                image = cached
            } else {
                image = await Task.detached(priority: .userInitiated) {
                    AppIconCache.loadIcon(for: url)
                }.value
            }
        }
    }
}
