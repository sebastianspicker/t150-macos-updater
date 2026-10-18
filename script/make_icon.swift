// Draws the app icon and writes AppIcon.icns and AppIcon.png into the given folder.
// Usage: script/make_icon.sh
import AppKit

guard CommandLine.arguments.count == 2 else { fatalError("usage: make_icon OUTPUT_DIRECTORY") }
let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}

/// Everything is drawn on a 1024-point canvas and scaled to the requested size.
func drawIcon(_ ctx: CGContext) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!

    // macOS icon grid: an 824-point rounded square centred on the canvas.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
    ctx.addPath(tilePath); ctx.setFillColor(color(0x161a22)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(tilePath); ctx.clip()
    let background = CGGradient(colorsSpace: space, colors: [color(0x2b3240), color(0x12151c)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(background, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    ctx.restoreGState()

    let centre = CGPoint(x: 512, y: 500)
    let rimRadius: CGFloat = 268, rimWidth: CGFloat = 62

    // Spokes: left, right and bottom, like a racing wheel.
    ctx.setStrokeColor(color(0xd5d9e0)); ctx.setLineCap(.round)
    ctx.setLineWidth(58)
    ctx.move(to: CGPoint(x: centre.x - rimRadius + 20, y: centre.y + 6)); ctx.addLine(to: CGPoint(x: centre.x + rimRadius - 20, y: centre.y + 6))
    ctx.strokePath()
    ctx.setLineWidth(52)
    ctx.move(to: centre); ctx.addLine(to: CGPoint(x: centre.x, y: centre.y - rimRadius + 24))
    ctx.strokePath()

    // Rim, drawn over the spoke ends.
    ctx.setLineCap(.butt)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 20, color: color(0x000000, 0.5))
    ctx.setLineWidth(rimWidth); ctx.setStrokeColor(color(0xe9ecf1))
    ctx.addArc(center: centre, radius: rimRadius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.strokePath()
    ctx.restoreGState()
    // Grip shading on the lower half of the rim.
    ctx.setLineWidth(rimWidth); ctx.setStrokeColor(color(0xc4c9d2))
    ctx.addArc(center: centre, radius: rimRadius, startAngle: .pi * 1.15, endAngle: .pi * 1.85, clockwise: false)
    ctx.strokePath()

    // Hub with a firmware chip.
    let hub = CGRect(x: centre.x - 96, y: centre.y - 96, width: 192, height: 192)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 14, color: color(0x000000, 0.45))
    ctx.setFillColor(color(0x1c212b)); ctx.fillEllipse(in: hub)
    ctx.restoreGState()
    let chip = CGRect(x: centre.x - 46, y: centre.y - 46, width: 92, height: 92)
    ctx.setFillColor(color(0xff7a1a))
    ctx.addPath(CGPath(roundedRect: chip, cornerWidth: 16, cornerHeight: 16, transform: nil)); ctx.fillPath()
    ctx.setStrokeColor(color(0xff7a1a)); ctx.setLineWidth(10); ctx.setLineCap(.round)
    for offset in [-26, 0, 26] as [CGFloat] {
        for (dx, dy) in [(0, 1), (0, -1), (1, 0), (-1, 0)] as [(CGFloat, CGFloat)] {
            let edge = CGPoint(x: centre.x + (dx == 0 ? offset : dx * 46), y: centre.y + (dy == 0 ? offset : dy * 46))
            ctx.move(to: edge); ctx.addLine(to: CGPoint(x: edge.x + dx * 18, y: edge.y + dy * 18))
        }
    }
    ctx.strokePath()
    ctx.setFillColor(color(0x1c212b))
    ctx.addPath(CGPath(roundedRect: chip.insetBy(dx: 22, dy: 22), cornerWidth: 6, cornerHeight: 6, transform: nil)); ctx.fillPath()

    // 12 o'clock marker on the rim, the way racing wheels show the centre.
    ctx.setStrokeColor(color(0xff7a1a)); ctx.setLineWidth(rimWidth + 2); ctx.setLineCap(.butt)
    ctx.addArc(center: centre, radius: rimRadius, startAngle: .pi / 2 - 0.13, endAngle: .pi / 2 + 0.13, clockwise: false)
    ctx.strokePath()
}

func png(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    let graphics = NSGraphicsContext(bitmapImageRep: rep)!
    let ctx = graphics.cgContext
    ctx.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    ctx.setShouldAntialias(true)
    drawIcon(ctx)
    graphics.flushGraphics()
    return rep.representation(using: .png, properties: [:])!
}

// An .icns file is a list of typed PNG entries behind an 8-byte header.
let entries: [(String, Int)] = [("icp4", 16), ("ic11", 32), ("icp5", 32), ("ic12", 64), ("ic07", 128),
                                ("ic13", 256), ("ic08", 256), ("ic14", 512), ("ic09", 512), ("ic10", 1024)]
func bigEndian(_ value: Int) -> Data { withUnsafeBytes(of: UInt32(value).bigEndian) { Data($0) } }
var body = Data()
for (type, size) in entries {
    let image = png(size: size)
    body += Data(type.utf8) + bigEndian(image.count + 8) + image
}
try (Data("icns".utf8) + bigEndian(body.count + 8) + body).write(to: outputDirectory.appendingPathComponent("AppIcon.icns"))
try png(size: 1024).write(to: outputDirectory.appendingPathComponent("AppIcon.png"))
