import AVFoundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import Vision

/// Turns a GIF, image or short video into a transparent, looping GIF. Runs once per import,
/// off the main thread; GlassDesk then just plays the saved file.
///
/// A GIF that is already transparent is used exactly as it is (see `isReadyToPlay`).
/// Anything else:
/// 1. Decode every frame (GIFs and images via ImageIO, videos via AVFoundation).
/// 2. Drop exact repeats, folding their time into the frame before.
/// 3. Cut (never blend) to the most seamless loop near the clip's ends, so the last frame
///    steps into the first like any other frame.
/// 4. Lift the subject out with Vision (keeping only the biggest subject, so watermarks
///    drop out), crop all frames to one shared box, and write an animated GIF.
///
/// Frames are never cross-faded or invented: a source with missing motion stays that way,
/// and the fix for a choppy source is a better source.
enum SpriteProcessor {
    struct Result {
        let frames: [CGImage]
        let delays: [Double]
    }

    /// Longer clips are trimmed; keeps memory and import time sensible.
    static let maxFrames = 300
    private static let context = CIContext()

    static func run(source: URL, removeBackground: Bool, progress: @escaping @Sendable (Double) -> Void) async -> Result? {
        guard var (frames, delays) = await decode(source), !frames.isEmpty else { return nil }
        let animated = frames.count > 2
        if animated {
            (frames, delays) = trimToLoop(frames, delays)
        }
        if removeBackground {
            var cutouts: [CGImage] = []
            for (index, frame) in frames.enumerated() {
                // If no subject is found in a frame, reuse the previous cut-out rather than
                // flashing the original background.
                cutouts.append(cutout(frame) ?? cutouts.last ?? frame)
                progress(Double(index + 1) / Double(frames.count))
            }
            frames = cropToSubject(cutouts)
        }
        return Result(frames: removeBackground ? frames.map(hardenAlpha) : frames, delays: delays)
    }

    /// True for a GIF whose background is already transparent: nothing to cut out, and
    /// re-encoding would only lose quality, so it gets copied as-is.
    static func isReadyToPlay(_ url: URL) -> Bool {
        guard url.pathExtension.lowercased() == "gif",
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let frame = CGImageSourceCreateImageAtIndex(source, 0, nil),
              frame.alphaInfo != .none, frame.alphaInfo != .noneSkipFirst, frame.alphaInfo != .noneSkipLast,
              let pixels = rgba(frame) else { return false }
        let width = frame.width, height = frame.height
        let corners = [0, width - 1, (height - 1) * width, height * width - 1]
        return corners.contains { pixels[$0 * 4 + 3] == 0 }
    }

    // MARK: Decoding

    private static func decode(_ url: URL) async -> ([CGImage], [Double])? {
        if let type = UTType(filenameExtension: url.pathExtension.lowercased()), type.conforms(to: .movie) {
            return await decodeVideo(url)
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        var frames: [CGImage] = []
        var delays: [Double] = []
        for index in 0..<min(CGImageSourceGetCount(source), maxFrames) {
            guard let frame = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            frames.append(frame)
            delays.append(gifDelay(source, index))
        }
        return (frames, delays)
    }

    private static func decodeVideo(_ url: URL) async -> ([CGImage], [Double])? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let reader = try? AVAssetReader(asset: asset) else { return nil }
        let transform = (try? await track.load(.preferredTransform)) ?? .identity
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        reader.add(output)
        guard reader.startReading() else { return nil }

        var frames: [CGImage] = []
        var times: [Double] = []
        while frames.count < maxFrames, let sample = output.copyNextSampleBuffer() {
            guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            let image = CIImage(cvPixelBuffer: buffer).transformed(by: transform)
            guard let frame = context.createCGImage(image, from: image.extent) else { continue }
            frames.append(frame)
            times.append(CMSampleBufferGetPresentationTimeStamp(sample).seconds)
        }
        reader.cancelReading()
        guard frames.count > 1 else { return frames.isEmpty ? nil : (frames, [0.1]) }
        var delays = zip(times.dropFirst(), times).map { max($0 - $1, 0.01) }
        delays.append(delays.last ?? 0.04)
        return (frames, delays)
    }

    private static func gifDelay(_ source: CGImageSource, _ index: Int) -> Double {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] ?? [:]
        let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] ?? [:]
        let value = (gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ?? (gif[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
        return value < 0.02 ? 0.1 : value  // browsers treat tiny delays as 0.1 s too
    }

    // MARK: Smoothing

    /// How different two frames look: mean absolute difference of small greyscale copies.
    private static func difference(_ a: [UInt8], _ b: [UInt8]) -> Double {
        Double(zip(a, b).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }) / Double(a.count)
    }

    private static func thumbnail(_ image: CGImage) -> [UInt8] {
        let width = 64, height = 64
        var pixels = [UInt8](repeating: 0, count: width * height)
        pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
            context.interpolationQuality = .medium
            context.setFillColor(gray: 0.5, alpha: 1)  // neutral backdrop for cut-outs
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return pixels
    }

    /// Steps 2 and 3: fold repeated frames, then cut the most seamless loop. The loop must
    /// keep most of the clip (its seam sits near the ends), because a spinning object often
    /// looks alike half a turn apart, which would otherwise pass for a seam.
    static func trimToLoop(_ frames: [CGImage], _ delays: [Double]) -> ([CGImage], [Double]) {
        let thumbs = frames.map(thumbnail)
        var kept = [0]
        var keptDelays = [delays[0]]
        for index in 1..<frames.count {
            if difference(thumbs[index], thumbs[kept.last!]) < 0.4 {
                keptDelays[keptDelays.count - 1] += delays[index]
            } else {
                kept.append(index)
                keptDelays.append(delays[index])
            }
        }
        let count = kept.count
        guard count > 8 else { return (kept.map { frames[$0] }, keptDelays) }
        func diff(_ a: Int, _ b: Int) -> Double { difference(thumbs[kept[a]], thumbs[kept[b]]) }

        // Frame `end` should look like frame `start`, so stepping from end-1 back to start
        // is as smooth as stepping on to `end` would have been.
        var start = 0, end = count
        var bestSeam = diff(count - 1, 0)  // cost of simply wrapping the whole clip
        let edge = max(1, count / 5)
        for a in 0..<edge {
            for b in (count - edge)..<count where b > a + 1 && diff(a, b) < bestSeam {
                bestSeam = diff(a, b)
                start = a
                end = b
            }
        }
        return ((start..<end).map { frames[kept[$0]] }, (start..<end).map { keptDelays[$0] })
    }

    // MARK: Background removal

    /// Lifts the main subject out of the frame. When Vision finds several subjects (an
    /// animal and a watermark, say), only the biggest one is kept.
    private static func cutout(_ image: CGImage) -> CGImage? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image)
        guard (try? handler.perform([request])) != nil,
              let observation = request.results?.first,
              !observation.allInstances.isEmpty else { return nil }

        var chosen = observation.allInstances
        if observation.allInstances.count > 1 {
            var bestArea = -1
            for instance in observation.allInstances {
                guard let mask = try? observation.generateScaledMaskForImage(forInstances: [instance], from: handler) else { continue }
                let area = coverage(of: mask)
                if area > bestArea {
                    bestArea = area
                    chosen = [instance]
                }
            }
        }
        guard let buffer = try? observation.generateMaskedImage(ofInstances: chosen, from: handler, croppedToInstancesExtent: false) else { return nil }
        let masked = CIImage(cvPixelBuffer: buffer)
        return context.createCGImage(masked, from: masked.extent)
    }

    /// Roughly how many pixels a mask covers (sampled on a grid; only relative size matters).
    private static func coverage(of mask: CVPixelBuffer) -> Int {
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(mask) else { return 0 }
        let width = CVPixelBufferGetWidth(mask), height = CVPixelBufferGetHeight(mask)
        let rowBytes = CVPixelBufferGetBytesPerRow(mask)
        var total = 0
        for y in stride(from: 0, to: height, by: 4) {
            let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: Float.self)
            for x in stride(from: 0, to: width, by: 4) where row[x] > 0.5 { total += 1 }
        }
        return total
    }

    // MARK: Pixels

    private static func rgba(_ image: CGImage) -> [UInt8]? {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? pixels : nil
    }

    /// Crops every frame to the union of where the subject appears in any frame, plus a
    /// little room, so the animation stays put and there's no empty canvas around it.
    private static func cropToSubject(_ frames: [CGImage]) -> [CGImage] {
        var union: CGRect?
        for frame in frames {
            guard let pixels = rgba(frame) else { continue }
            let width = frame.width
            var minX = width, minY = frame.height, maxX = -1, maxY = -1
            for y in 0..<frame.height {
                for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 16 {
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
            guard maxX >= minX else { continue }
            let box = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
            union = union.map { $0.union(box) } ?? box
        }
        guard let first = frames.first, var box = union else { return frames }
        box = box.insetBy(dx: -4, dy: -4).intersection(CGRect(x: 0, y: 0, width: first.width, height: first.height)).integral
        return frames.map { $0.cropping(to: box) ?? $0 }
    }

    /// GIF transparency is all-or-nothing, so decide each edge pixel ourselves: at least
    /// half opaque becomes fully opaque (un-premultiplied, so edges don't darken), anything
    /// less becomes clear.
    private static func hardenAlpha(_ image: CGImage) -> CGImage {
        guard var pixels = rgba(image) else { return image }
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Int(pixels[index + 3])
            if alpha >= 128 {
                for channel in 0..<3 {
                    pixels[index + channel] = UInt8(min(255, Int(pixels[index + channel]) * 255 / alpha))
                }
                pixels[index + 3] = 255
            } else {
                pixels[index] = 0; pixels[index + 1] = 0; pixels[index + 2] = 0; pixels[index + 3] = 0
            }
        }
        let width = image.width, height = image.height
        return pixels.withUnsafeMutableBytes { buffer -> CGImage? in
            CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                      bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        } ?? image
    }

    // MARK: Saving

    /// Writes an endlessly looping animated GIF with transparency.
    @discardableResult
    static func writeGIF(_ result: Result, to url: URL) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString,
                                                                result.frames.count, nil) else { return false }
        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],
        ] as CFDictionary)
        for (frame, delay) in zip(result.frames, result.delays) {
            CGImageDestinationAddImage(destination, frame, [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFDelayTime: delay,
                    kCGImagePropertyGIFUnclampedDelayTime: delay,
                ],
            ] as CFDictionary)
        }
        return CGImageDestinationFinalize(destination)
    }

    /// Reads an animated GIF (or any image) back as frames and delays. Frames are decoded
    /// up front: otherwise every frame would be re-decoded from GIF data each time it shows.
    static func readGIF(_ url: URL) -> Result? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let decodeNow = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        var frames: [CGImage] = []
        var delays: [Double] = []
        for index in 0..<CGImageSourceGetCount(source) {
            guard let frame = CGImageSourceCreateImageAtIndex(source, index, decodeNow) else { continue }
            frames.append(frame)
            delays.append(gifDelay(source, index))
        }
        return frames.isEmpty ? nil : Result(frames: frames, delays: delays)
    }
}
