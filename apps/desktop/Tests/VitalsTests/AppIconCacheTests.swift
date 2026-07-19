import Testing
import AppKit
@testable import Vitals

/// Locks the icon-cache fix: `flatten` must collapse a big multi-rep icon into
/// one small baked bitmap. Regressing this is what let the cache grow to
/// hundreds of MB (full-res ICNS reps kept resident despite a 32-pt draw size).
struct AppIconCacheTests {
    /// A stand-in for `NSWorkspace.icon(forFile:)`: a 1024×1024 image carrying a
    /// second, larger representation — exactly the multi-rep shape that bloats.
    private func fatIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 1024, height: 1024))
        for side in [512, 1024] {
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            image.addRepresentation(rep)
        }
        return image
    }

    @Test func flattenCollapsesToOneSmallBitmap() {
        let flat = AppIconCache.flatten(fatIcon())
        // Exactly one representation survives — the baked bitmap, not the reps.
        #expect(flat.representations.count == 1)
        // Logical draw size is 32 pt; the backing bitmap is 64 px (32 pt @2x),
        // so it's crisp on Retina but tiny in memory (~16 KB, not ~4 MB).
        #expect(flat.size == NSSize(width: 32, height: 32))
        let rep = flat.representations.first as? NSBitmapImageRep
        #expect(rep?.pixelsWide == 64)
        #expect(rep?.pixelsHigh == 64)
    }
}
