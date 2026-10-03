// Draws a small animated sprite (a bouncing glass bubble) for the README photos, so they don't
// need anyone's own GIF.
//
//   xcrun swift scripts/make-demo-gif.swift /path/to/demo-folder
//
// Writes <folder>/Sprite/sprite.gif and sprite.json, which is where GlassDesk looks when it is run
// with GLASSDESK_DEMO=1 and GLASSDESK_DEMO_FOLDER=<folder>.

import AppKit
import ImageIO
import UniformTypeIdentifiers

let folder = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/glassdesk-demo")
let spriteFolder = folder.appending(path: "Sprite")
try! FileManager.default.createDirectory(at: spriteFolder, withIntermediateDirectories: true)

let side = 220
let frameCount = 24

func frame(_ index: Int) -> CGImage {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
                                  samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                  bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current?.imageInterpolation = .high

    let t = Double(index) / Double(frameCount)
    // A bounce: up and down once per loop, flattening a little as it lands.
    let height = abs(sin(t * .pi))
    let squash = 1 + 0.16 * pow(1 - height, 6)
    let radius = 70.0
    let centerX = Double(side) / 2
    let centerY = 54 + 60 * height + radius * (squash - 1) * -0.5
    let width = radius * 2 * squash
    let tall = radius * 2 / squash
    let body = CGRect(x: centerX - width / 2, y: centerY - tall / 2 + 40, width: width, height: tall)

    // A shadow on the ground that shrinks as the bubble rises.
    let shadowWidth = 110 - 40 * height
    NSColor.black.withAlphaComponent(0.22 - 0.08 * height).setFill()
    NSBezierPath(ovalIn: CGRect(x: centerX - shadowWidth / 2, y: 20, width: shadowWidth, height: 16)).fill()

    // The bubble: a violet-to-pink body with a bright rim and a highlight.
    let path = NSBezierPath(ovalIn: body)
    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    NSGradient(colors: [NSColor(srgbRed: 0.98, green: 0.45, blue: 0.75, alpha: 1), NSColor(srgbRed: 0.45, green: 0.35, blue: 0.95, alpha: 1)])!
        .draw(in: body, angle: -60)
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.5), NSColor.white.withAlphaComponent(0)])!
        .draw(fromCenter: CGPoint(x: body.midX - 22, y: body.midY + 30), radius: 0,
              toCenter: CGPoint(x: body.midX - 22, y: body.midY + 30), radius: 70, options: [])
    NSGraphicsContext.restoreGraphicsState()
    NSColor.white.withAlphaComponent(0.8).setStroke()
    path.lineWidth = 3
    path.stroke()

    // Two eyes that blink once in the middle of the loop.
    let blinking = index == frameCount / 2
    NSColor(srgbRed: 0.12, green: 0.08, blue: 0.3, alpha: 1).setFill()
    for offset in [-20.0, 20.0] {
        let eye = CGRect(x: body.midX + offset - 7, y: body.midY + 2, width: 14, height: blinking ? 3 : 20)
        NSBezierPath(roundedRect: eye, xRadius: 7, yRadius: 7).fill()
    }
    NSColor(srgbRed: 1, green: 0.7, blue: 0.8, alpha: 0.9).setFill()
    for offset in [-40.0, 40.0] {
        NSBezierPath(ovalIn: CGRect(x: body.midX + offset - 9, y: body.midY - 14, width: 18, height: 11)).fill()
    }

    NSGraphicsContext.restoreGraphicsState()
    return bitmap.cgImage!
}

let url = spriteFolder.appending(path: "sprite.gif")
let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frameCount, nil)!
CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
for index in 0..<frameCount {
    CGImageDestinationAddImage(destination, frame(index), [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.05]] as CFDictionary)
}
CGImageDestinationFinalize(destination)
try! #"{"backgroundRemoved":true}"#.write(to: spriteFolder.appending(path: "sprite.json"), atomically: true, encoding: .utf8)
print("Wrote \(url.path)")
