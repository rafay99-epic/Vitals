// Renders the app icon (1024x1024 PNG) — run by build.sh, not part of the app.
import AppKit

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
let size = 1024

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { fatalError("could not create bitmap") }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let rect = NSRect(x: 0, y: 0, width: size, height: size)
let rounded = NSBezierPath(roundedRect: rect, xRadius: 234, yRadius: 234)
rounded.addClip()

NSGradient(
    starting: NSColor(calibratedRed: 0.07, green: 0.13, blue: 0.27, alpha: 1),
    ending: NSColor(calibratedRed: 0.12, green: 0.45, blue: 0.62, alpha: 1)
)?.draw(in: rect, angle: 60)

let config = NSImage.SymbolConfiguration(pointSize: 540, weight: .medium)
    .applying(.init(paletteColors: [.white]))
if let symbol = NSImage(systemSymbolName: "gauge.with.dots.needle.50percent", accessibilityDescription: nil)?
    .withSymbolConfiguration(config) {
    let target = NSRect(x: 192, y: 192, width: 640, height: 640)
    symbol.draw(in: target, from: .zero, operation: .sourceOver, fraction: 0.95)
}

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("png encode failed") }
try! png.write(to: URL(fileURLWithPath: outputPath))
print("wrote \(outputPath)")
