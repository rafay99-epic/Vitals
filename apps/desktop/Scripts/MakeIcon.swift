// Renders the app icon (1024x1024 PNG) — run by build.sh, not part of the app.
// The mark matches the website logo: red heartbeat line on a dark gradient
// squircle (linear-gradient(160deg, #2a2a2e, #161618), stroke #FF453A).
import AppKit

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
// Second arg picks the channel: "nightly" and "dev" recolor the heartbeat and
// stamp a badge so the Dock instantly distinguishes them from Stable.
let channel = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "stable"
func rgb(_ r: Int, _ g: Int, _ b: Int) -> NSColor {
    NSColor(calibratedRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
}
let accent: NSColor
let badgeLabel: String?
switch channel {
case "nightly":
    accent = rgb(0xff, 0x9f, 0x0a)  // amber
    badgeLabel = "NIGHTLY"
case "dev":
    accent = rgb(0xbf, 0x5a, 0xf2)  // purple
    badgeLabel = "DEV"
default:
    accent = rgb(0xff, 0x45, 0x3a)  // red
    badgeLabel = nil
}
let size = 1024

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { fatalError("could not create bitmap") }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// macOS icon grid: an 824x824 squircle centered on the 1024 canvas.
let inset: CGFloat = 100
let box = NSRect(x: inset, y: inset, width: 824, height: 824)
let radius: CGFloat = 185
let squircle = NSBezierPath(roundedRect: box, xRadius: radius, yRadius: radius)

// Soft drop shadow like system icons.
NSGraphicsContext.current?.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
shadow.shadowOffset = NSSize(width: 0, height: -14)
shadow.shadowBlurRadius = 28
shadow.set()
NSColor(calibratedWhite: 0.09, alpha: 1).setFill()
squircle.fill()
NSGraphicsContext.current?.restoreGraphicsState()

// Dark gradient fill (website: linear-gradient(160deg, #2a2a2e, #161618)).
NSGraphicsContext.current?.saveGraphicsState()
squircle.addClip()
NSGradient(
    starting: NSColor(calibratedRed: 0x2a / 255.0, green: 0x2a / 255.0, blue: 0x2e / 255.0, alpha: 1),
    ending: NSColor(calibratedRed: 0x16 / 255.0, green: 0x16 / 255.0, blue: 0x18 / 255.0, alpha: 1)
)?.draw(in: box, angle: -70)
NSGraphicsContext.current?.restoreGraphicsState()

// Hairline border (website: 1px rgba(255,255,255,0.12)).
let borderWidth: CGFloat = 12
let borderPath = NSBezierPath(
    roundedRect: box.insetBy(dx: borderWidth / 2, dy: borderWidth / 2),
    xRadius: radius - borderWidth / 2, yRadius: radius - borderWidth / 2
)
borderPath.lineWidth = borderWidth
NSColor(calibratedWhite: 1, alpha: 0.12).setStroke()
borderPath.stroke()

// Heartbeat polyline, traced from the website logo's 24x24 viewBox
// (SVG y-down coordinates flipped for AppKit).
let points: [(CGFloat, CGFloat)] = [
    (1, 12), (6, 12), (8, 12), (9.4, 5), (11, 19), (12.8, 9.5), (14.5, 14), (16, 12), (23, 12),
]
let scale = box.width * 0.68 / 24
let originX = box.minX + (box.width - 24 * scale) / 2
let originY = box.minY + (box.height - 24 * scale) / 2

let line = NSBezierPath()
for (index, point) in points.enumerated() {
    let converted = NSPoint(x: originX + point.0 * scale, y: originY + (24 - point.1) * scale)
    if index == 0 { line.move(to: converted) } else { line.line(to: converted) }
}
line.lineWidth = 1.7 * scale
line.lineCapStyle = .round
line.lineJoinStyle = .round
accent.setStroke()
line.stroke()

// Channel badge: a pill near the bottom of the squircle, below the heartbeat.
// Longer labels (NIGHTLY) shrink so they don't overflow the squircle.
if let badgeLabel {
    let label = badgeLabel as NSString
    let font = NSFont.systemFont(ofSize: badgeLabel.count > 3 ? 84 : 118, weight: .heavy)
    let textAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
    let textSize = label.size(withAttributes: textAttrs)
    let padX: CGFloat = 56, padY: CGFloat = 22
    let badgeW = textSize.width + padX * 2
    let badgeH = textSize.height + padY * 2
    let badgeRect = NSRect(x: box.midX - badgeW / 2, y: box.minY + 60, width: badgeW, height: badgeH)
    let badge = NSBezierPath(roundedRect: badgeRect, xRadius: badgeH / 2, yRadius: badgeH / 2)
    accent.setFill()
    badge.fill()
    NSColor(calibratedWhite: 1, alpha: 0.9).setStroke()
    badge.lineWidth = 6
    badge.stroke()
    label.draw(at: NSPoint(x: badgeRect.midX - textSize.width / 2,
                           y: badgeRect.midY - textSize.height / 2), withAttributes: textAttrs)
}

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("png encode failed") }
try! png.write(to: URL(fileURLWithPath: outputPath))
print("wrote \(outputPath)")
