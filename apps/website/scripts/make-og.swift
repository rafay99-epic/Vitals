// Renders the Open Graph / social share image (1200x630) → public/og.png.
// A local one-off generator (macOS/AppKit); the PNG is committed, so CI just
// serves it. Run from the website dir:  swift scripts/make-og.swift public/og.png
import AppKit

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "og.png"
let W = 1200, H = 630

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { fatalError("no bitmap") }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: CGFloat(r)/255, green: CGFloat(g)/255, blue: CGFloat(b)/255, alpha: a)
}

// Background.
rgb(6, 6, 8).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: W, height: H)).fill()

// Aurora-ish glows (radial), echoing the site.
func glow(_ cx: CGFloat, _ cy: CGFloat, _ radius: CGFloat, _ color: NSColor) {
    let colors = [color.cgColor, color.withAlphaComponent(0).cgColor] as CFArray
    guard let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return }
    ctx.saveGState()
    ctx.drawRadialGradient(grad, startCenter: CGPoint(x: cx, y: cy), startRadius: 0,
                           endCenter: CGPoint(x: cx, y: cy), endRadius: radius, options: [])
    ctx.restoreGState()
}
glow(330, CGFloat(H) + 40, 620, rgb(10, 132, 255, 0.5))
glow(CGFloat(W) - 120, CGFloat(H) - 60, 480, rgb(255, 159, 10, 0.18))
glow(120, 120, 460, rgb(50, 215, 75, 0.12))

// Brand icon: a small dark squircle with the red heartbeat (matches the app icon).
let iconSize: CGFloat = 132
let iconX: CGFloat = 80, iconY = CGFloat(H) - 80 - iconSize
let iconBox = NSRect(x: iconX, y: iconY, width: iconSize, height: iconSize)
let squircle = NSBezierPath(roundedRect: iconBox, xRadius: 30, yRadius: 30)
NSGradient(starting: rgb(0x2a, 0x2a, 0x2e), ending: rgb(0x16, 0x16, 0x18))?.draw(in: iconBox, angle: -70)
squircle.addClip()
NSGraphicsContext.current!.cgContext.resetClip()
rgb(255, 255, 255, 0.12).setStroke()
let border = NSBezierPath(roundedRect: iconBox.insetBy(dx: 1, dy: 1), xRadius: 29, yRadius: 29)
border.lineWidth = 1.5
border.stroke()

func heartbeat(in box: NSRect, width: CGFloat, color: NSColor, alpha: CGFloat = 1) {
    let pts: [(CGFloat, CGFloat)] = [
        (1, 12), (6, 12), (8, 12), (9.4, 5), (11, 19), (12.8, 9.5), (14.5, 14), (16, 12), (23, 12),
    ]
    let s = box.width / 24
    let ox = box.minX, oy = box.minY
    let line = NSBezierPath()
    for (i, p) in pts.enumerated() {
        let cp = NSPoint(x: ox + p.0 * s, y: oy + (24 - p.1) * s)
        if i == 0 { line.move(to: cp) } else { line.line(to: cp) }
    }
    line.lineWidth = width
    line.lineCapStyle = .round
    line.lineJoinStyle = .round
    color.withAlphaComponent(alpha).setStroke()
    line.stroke()
}
heartbeat(in: iconBox.insetBy(dx: iconSize * 0.16, dy: iconSize * 0.16), width: 9, color: rgb(0xff, 0x45, 0x3a))

// "Vitals" wordmark beside the icon.
func draw(_ text: String, _ font: NSFont, _ color: NSColor, at p: NSPoint) {
    (text as NSString).draw(at: p, withAttributes: [.font: font, .foregroundColor: color])
}
draw("Vitals", NSFont.systemFont(ofSize: 56, weight: .semibold), .white,
     at: NSPoint(x: iconX + iconSize + 26, y: iconY + (iconSize - 66) / 2))

// Headline.
let h1 = NSFont.systemFont(ofSize: 82, weight: .bold)
draw("Your Mac has a dashboard.", h1, .white, at: NSPoint(x: 80, y: 250))
let muted = NSMutableParagraphStyle()
let line2 = NSMutableAttributedString(string: "Apple just ", attributes: [.font: h1, .foregroundColor: NSColor.white, .paragraphStyle: muted])
line2.append(NSAttributedString(string: "hid it.", attributes: [.font: h1, .foregroundColor: rgb(0x1a, 0x8c, 0xff), .paragraphStyle: muted]))
line2.draw(at: NSPoint(x: 80, y: 150))

// Footer line.
draw("Free & open source  ·  vitals.rafay99.com", NSFont.systemFont(ofSize: 26, weight: .medium),
     rgb(235, 235, 245, 0.5), at: NSPoint(x: 80, y: 70))

NSGraphicsContext.restoreGraphicsState()
guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("png fail") }
try! png.write(to: URL(fileURLWithPath: outputPath))
print("wrote \(outputPath)")
