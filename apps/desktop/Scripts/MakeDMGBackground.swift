// Renders the DMG installer background (660x400 points @2x) — run by
// make-dmg.sh, not part of the app.
import AppKit

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "dmg-background.png"
let width = 660
let height = 400
let scale = 2

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: width * scale, pixelsHigh: height * scale,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { fatalError("could not create bitmap") }
// Point size half the pixel size → 144 dpi, so Finder renders it Retina-crisp.
rep.size = NSSize(width: width, height: height)

NSGraphicsContext.saveGraphicsState()
let context = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = context
context.cgContext.scaleBy(x: CGFloat(scale), y: CGFloat(scale))

let rect = NSRect(x: 0, y: 0, width: width, height: height)
NSGradient(
    starting: NSColor(calibratedWhite: 0.99, alpha: 1),
    ending: NSColor(calibratedWhite: 0.93, alpha: 1)
)!.draw(in: rect, angle: -90)

func drawCentered(_ string: String, font: NSFont, color: NSColor, centerX: CGFloat, y: CGFloat) {
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let size = string.size(withAttributes: attributes)
    string.draw(at: NSPoint(x: centerX - size.width / 2, y: y), withAttributes: attributes)
}

drawCentered(
    "Vitals",
    font: .systemFont(ofSize: 30, weight: .semibold),
    color: NSColor(calibratedWhite: 0.20, alpha: 1),
    centerX: 330, y: 338
)
drawCentered(
    "Drag the app into Applications to install",
    font: .systemFont(ofSize: 14),
    color: NSColor(calibratedWhite: 0.45, alpha: 1),
    centerX: 330, y: 312
)

// Arrow between the two icon positions (icons sit at y 205 from the top,
// which is y 195 from the bottom in this coordinate space).
let arrowColor = NSColor(calibratedWhite: 0.62, alpha: 1)
arrowColor.setStroke()
arrowColor.setFill()

let shaft = NSBezierPath()
shaft.lineWidth = 5
shaft.lineCapStyle = .round
shaft.move(to: NSPoint(x: 262, y: 195))
shaft.line(to: NSPoint(x: 386, y: 195))
shaft.stroke()

let head = NSBezierPath()
head.move(to: NSPoint(x: 382, y: 211))
head.line(to: NSPoint(x: 408, y: 195))
head.line(to: NSPoint(x: 382, y: 179))
head.close()
head.fill()

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("png encode failed") }
try! png.write(to: URL(fileURLWithPath: outputPath))
print("wrote \(outputPath)")
