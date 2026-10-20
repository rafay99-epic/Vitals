import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "assets", isDirectory: true)
let size = 1024

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
        green: CGFloat((hex >> 8) & 0xff) / 255,
        blue: CGFloat(hex & 0xff) / 255,
        alpha: alpha
    )
}

let pulse = color(0x5cf2a6)
let devBadge = color(0xc8a8ff)
let beatPoints: [CGPoint] = [
    CGPoint(x: 2, y: 18), CGPoint(x: 12, y: 18), CGPoint(x: 16, y: 26),
    CGPoint(x: 24, y: 4), CGPoint(x: 28, y: 18), CGPoint(x: 46, y: 18),
]

struct Asset {
    let name: String
    let background: NSColor?
    let ink: NSColor
    let beatWidth: CGFloat
    let badge: Bool
    var mono = false
}

func beat(width: CGFloat, center: CGPoint) -> NSBezierPath {
    let scale = width / 44
    let path = NSBezierPath()
    for (index, point) in beatPoints.enumerated() {
        let mapped = CGPoint(x: center.x + (point.x - 24) * scale, y: center.y - (point.y - 15) * scale)
        if index == 0 { path.move(to: mapped) } else { path.line(to: mapped) }
    }
    path.lineWidth = 2.6 * scale
    path.lineJoinStyle = .round
    path.lineCapStyle = .round
    return path
}

func drawBadge(in canvas: CGFloat, mono: Bool) {
    let label = NSAttributedString(string: "DEV", attributes: [
        .font: NSFont.monospacedSystemFont(ofSize: canvas * 0.075, weight: .semibold),
        .foregroundColor: NSColor.black,
        .kern: canvas * 0.006,
    ])
    let textSize = label.size()
    let padX = canvas * 0.03
    let padY = canvas * 0.012
    let box = NSRect(
        x: (canvas - textSize.width) / 2 - padX,
        y: canvas * 0.2,
        width: textSize.width + padX * 2,
        height: textSize.height + padY * 2
    )
    (mono ? NSColor.white : devBadge).setFill()
    NSBezierPath(rect: box).fill()
    if mono { NSGraphicsContext.current?.cgContext.setBlendMode(.destinationOut) }
    label.draw(at: NSPoint(x: box.minX + padX, y: box.minY + padY))
    NSGraphicsContext.current?.cgContext.setBlendMode(.normal)
}

func render(_ asset: Asset) throws {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { throw NSError(domain: "brand", code: 1) }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let canvas = CGFloat(size)
    if let background = asset.background {
        background.setFill()
        NSRect(x: 0, y: 0, width: canvas, height: canvas).fill()
    }
    asset.ink.setStroke()
    beat(width: canvas * asset.beatWidth, center: CGPoint(x: canvas / 2, y: canvas / 2 + (asset.badge ? canvas * 0.05 : 0))).stroke()
    if asset.badge { drawBadge(in: canvas, mono: asset.mono) }
    NSGraphicsContext.restoreGraphicsState()
    guard let png = rep.representation(using: .png, properties: [:]) else { throw NSError(domain: "brand", code: 2) }
    try png.write(to: output.appendingPathComponent("\(asset.name).png"))
}

let white = NSColor.white
let assets: [Asset] = [false, true].flatMap { dev -> [Asset] in
    let suffix = dev ? "-dev" : ""
    return [
        Asset(name: "icon\(suffix)", background: .black, ink: pulse, beatWidth: 0.62, badge: dev),
        Asset(name: "icon-dark\(suffix)", background: nil, ink: pulse, beatWidth: 0.62, badge: dev),
        Asset(name: "icon-tinted\(suffix)", background: nil, ink: white, beatWidth: 0.62, badge: dev),
        Asset(name: "adaptive-foreground\(suffix)", background: nil, ink: pulse, beatWidth: 0.42, badge: dev),
        Asset(name: "adaptive-monochrome\(suffix)", background: nil, ink: white, beatWidth: 0.42, badge: dev, mono: true),
    ]
} + [
    Asset(name: "splash", background: nil, ink: pulse, beatWidth: 0.9, badge: false),
]

try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for asset in assets { try render(asset) }
print("rendered \(assets.count) assets into \(output.path)")
