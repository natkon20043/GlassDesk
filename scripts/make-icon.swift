// Draws the GlassDesk app icon and writes Resources/GlassDesk.icns.
//
//   xcrun swift scripts/make-icon.swift
//
// The icon is drawn in code (no image editor needed), so it can be tweaked and regenerated.
// It shows what the app is: translucent glass widget cards over a colourful backdrop, one of them
// with the activity rings of the Vitals widget, and the sparkle that is GlassDesk's menu bar icon.

import AppKit

let artboard: CGFloat = 1024

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha)
}

/// A four-pointed sparkle with concave sides.
func sparklePath(center: CGPoint, radius: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    let pinch = radius * 0.16
    path.move(to: CGPoint(x: center.x, y: center.y + radius))
    path.curve(to: CGPoint(x: center.x + radius, y: center.y),
               controlPoint1: CGPoint(x: center.x + pinch, y: center.y + pinch),
               controlPoint2: CGPoint(x: center.x + pinch, y: center.y + pinch))
    path.curve(to: CGPoint(x: center.x, y: center.y - radius),
               controlPoint1: CGPoint(x: center.x + pinch, y: center.y - pinch),
               controlPoint2: CGPoint(x: center.x + pinch, y: center.y - pinch))
    path.curve(to: CGPoint(x: center.x - radius, y: center.y),
               controlPoint1: CGPoint(x: center.x - pinch, y: center.y - pinch),
               controlPoint2: CGPoint(x: center.x - pinch, y: center.y - pinch))
    path.curve(to: CGPoint(x: center.x, y: center.y + radius),
               controlPoint1: CGPoint(x: center.x - pinch, y: center.y + pinch),
               controlPoint2: CGPoint(x: center.x - pinch, y: center.y + pinch))
    path.close()
    return path
}

/// A rounded rectangle of translucent glass: a faint fill, a brighter top, and a thin bright rim.
func drawGlassCard(_ rect: CGRect, cornerRadius: CGFloat, strength: CGFloat) {
    let shape = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = 34
    shadow.shadowOffset = NSSize(width: 0, height: -14)
    shadow.set()
    color(0xFFFFFF, alpha: 0.10 * strength).setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    let sheen = NSGradient(colors: [color(0xFFFFFF, alpha: 0.34 * strength), color(0xFFFFFF, alpha: 0.06 * strength)])!
    sheen.draw(in: rect, angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    let rim = NSBezierPath(roundedRect: rect.insetBy(dx: 1.5, dy: 1.5), xRadius: cornerRadius - 1.5, yRadius: cornerRadius - 1.5)
    rim.lineWidth = 3
    NSGraphicsContext.saveGraphicsState()
    rim.addClip()
    let rimGradient = NSGradient(colors: [color(0xFFFFFF, alpha: 0.75 * strength), color(0xFFFFFF, alpha: 0.12 * strength)])!
    rimGradient.draw(in: rect, angle: -90)
    NSGraphicsContext.restoreGraphicsState()
    color(0xFFFFFF, alpha: 0.30 * strength).setStroke()
    rim.stroke()
}

/// One ring of the activity rings: a faint track and a bright arc over it.
func drawRing(center: CGPoint, radius: CGFloat, width: CGFloat, fraction: CGFloat, tint: NSColor) {
    let track = NSBezierPath()
    track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
    track.lineWidth = width
    tint.withAlphaComponent(0.28).setStroke()
    track.stroke()

    let arc = NSBezierPath()
    arc.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: 90 - 360 * fraction, clockwise: true)
    arc.lineWidth = width
    arc.lineCapStyle = .round
    tint.setStroke()
    arc.stroke()
}

func drawIcon() {
    // macOS icons sit inside the artboard with room for a shadow.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = NSBezierPath(roundedRect: body, xRadius: 186, yRadius: 186)

    NSGraphicsContext.saveGraphicsState()
    let outerShadow = NSShadow()
    outerShadow.shadowColor = NSColor.black.withAlphaComponent(0.38)
    outerShadow.shadowBlurRadius = 30
    outerShadow.shadowOffset = NSSize(width: 0, height: -14)
    outerShadow.set()
    color(0x30206E).setFill()
    squircle.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    squircle.addClip()

    // The backdrop the glass sits on: indigo into violet, pink and a warm corner.
    let backdrop = NSGradient(colorsAndLocations:
        (color(0x1B1550), 0.0), (color(0x5B2DB8), 0.34), (color(0xD0388F), 0.70), (color(0xFF9A4D), 1.0))!
    backdrop.draw(in: body, angle: -55)
    // A soft light from the top left.
    let glow = NSGradient(colors: [color(0xB9A4FF, alpha: 0.30), color(0xB9A4FF, alpha: 0)])!
    glow.draw(fromCenter: CGPoint(x: 300, y: 820), radius: 0, toCenter: CGPoint(x: 300, y: 820), radius: 460, options: [])

    // The smaller card behind, peeking out to the upper right.
    drawGlassCard(CGRect(x: 520, y: 560, width: 300, height: 210), cornerRadius: 56, strength: 0.85)
    // Two lines of text on it, as a widget would have.
    color(0xFFFFFF, alpha: 0.80).setFill()
    NSBezierPath(roundedRect: CGRect(x: 566, y: 700, width: 150, height: 26), xRadius: 13, yRadius: 13).fill()
    color(0xFFFFFF, alpha: 0.45).setFill()
    NSBezierPath(roundedRect: CGRect(x: 566, y: 650, width: 200, height: 20), xRadius: 10, yRadius: 10).fill()
    NSBezierPath(roundedRect: CGRect(x: 566, y: 606, width: 120, height: 20), xRadius: 10, yRadius: 10).fill()

    // The main card in front, with the activity rings.
    let front = CGRect(x: 190, y: 250, width: 500, height: 340)
    drawGlassCard(front, cornerRadius: 68, strength: 1.0)
    let ringCenter = CGPoint(x: 390, y: 420)
    drawRing(center: ringCenter, radius: 110, width: 36, fraction: 0.78, tint: color(0xFF4F7B))
    drawRing(center: ringCenter, radius: 70, width: 36, fraction: 0.62, tint: color(0xA6F04D))
    drawRing(center: ringCenter, radius: 30, width: 30, fraction: 0.45, tint: color(0x4FC9FF))

    // Figures beside the rings.
    let bars: [(CGFloat, CGFloat, NSColor)] = [(150, 480, color(0xFF4F7B)), (120, 430, color(0xA6F04D)), (135, 380, color(0x4FC9FF))]
    for (width, y, tint) in bars {
        tint.setFill()
        NSBezierPath(roundedRect: CGRect(x: 530, y: y, width: width * 0.62, height: 30), xRadius: 15, yRadius: 15).fill()
    }

    // The sparkle: GlassDesk's menu bar icon.
    color(0xFFFFFF).setFill()
    sparklePath(center: CGPoint(x: 748, y: 812), radius: 70).fill()
    color(0xFFFFFF, alpha: 0.9).setFill()
    sparklePath(center: CGPoint(x: 646, y: 738), radius: 28).fill()
    sparklePath(center: CGPoint(x: 846, y: 690), radius: 24).fill()

    NSGraphicsContext.restoreGraphicsState()

    // A hairline of light around the whole icon.
    let edge = NSBezierPath(roundedRect: body.insetBy(dx: 1, dy: 1), xRadius: 185, yRadius: 185)
    edge.lineWidth = 2
    color(0xFFFFFF, alpha: 0.35).setStroke()
    edge.stroke()
}

func renderPNG(pixels: Int) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                  samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                  bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let scale = CGFloat(pixels) / artboard
    NSGraphicsContext.current?.cgContext.scaleBy(x: scale, y: scale)
    NSGraphicsContext.current?.imageInterpolation = .high
    drawIcon()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

// The sizes an .icns needs, each in 1x and 2x.
let files: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

let root = URL(fileURLWithPath: CommandLine.arguments.first.map { _ in FileManager.default.currentDirectoryPath }!)
let iconset = root.appendingPathComponent(".build/GlassDesk.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for file in files {
    try! renderPNG(pixels: file.pixels).write(to: iconset.appendingPathComponent(file.name + ".png"))
}
// A full-size copy for the README and the GitHub page.
try! FileManager.default.createDirectory(at: root.appendingPathComponent("docs/images"), withIntermediateDirectories: true)
try! renderPNG(pixels: 512).write(to: root.appendingPathComponent("docs/images/icon.png"))

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/GlassDesk.icns").path]
try! process.run()
process.waitUntilExit()
print("Wrote Resources/GlassDesk.icns and docs/images/icon.png")
