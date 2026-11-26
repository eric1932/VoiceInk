// Before/after material for release notes: two screen recordings stacked (before on top),
// each with a small label in its top-left corner.
//
//   compare still <before.mov> <t> <after.mov> <t> <out.png>
//   compare video <before.mov> <start> <after.mov> <start> <seconds> <out.mp4>
//   compare gif   <in.mp4> <out.gif> [fps=10] [width=640]
//
// Env: CROP="x,y,w,h" (pixels, applied to both clips), BEFORE_LABEL, AFTER_LABEL.
// Build: swiftc -O -parse-as-library compare.swift -o compare
import AVFoundation
import AppKit
import ImageIO
import UniformTypeIdentifiers

let env = ProcessInfo.processInfo.environment
let beforeLabel = env["BEFORE_LABEL"] ?? "Before · VoiceInk 2.25"
let afterLabel = env["AFTER_LABEL"] ?? "After · ui-polish"
let labelFont = NSFont.systemFont(ofSize: 22, weight: .semibold)
let labelInset = CGPoint(x: 18, y: 16)

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

func cropRect(full: CGSize) -> CGRect {
    guard let spec = env["CROP"] else { return CGRect(origin: .zero, size: full) }
    let n = spec.split(separator: ",").compactMap { Double($0) }
    guard n.count == 4 else { fail("CROP must be x,y,w,h") }
    return CGRect(x: n[0], y: n[1], width: n[2], height: n[3])
}

func seconds(_ value: Double) -> CMTime { CMTime(seconds: value, preferredTimescale: 600) }

/// Label pill size for `text`.
func pillSize(_ text: String) -> CGSize {
    let size = (text as NSString).size(withAttributes: [.font: labelFont])
    return CGSize(width: ceil(size.width) + 24, height: ceil(size.height) + 10)
}

// MARK: still

func frame(_ url: URL, at time: Double) async throws -> CGImage {
    let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    return try await generator.image(at: seconds(time)).image
}

func drawLabel(_ text: String, panelTop: CGFloat, origin: CGPoint = labelInset) {
    // Flipped context: y grows downward.
    let size = pillSize(text)
    let rect = CGRect(origin: CGPoint(x: origin.x, y: panelTop + labelInset.y), size: size)
    NSColor.black.withAlphaComponent(0.6).setFill()
    NSBezierPath(roundedRect: rect, xRadius: size.height / 2, yRadius: size.height / 2).fill()
    (text as NSString).draw(
        at: CGPoint(x: rect.minX + 12, y: rect.minY + 5),
        withAttributes: [.font: labelFont, .foregroundColor: NSColor.white])
}

func still(_ args: [String]) async throws {
    guard args.count == 5, let tb = Double(args[1]), let ta = Double(args[3]) else {
        fail("compare still <before.mov> <t> <after.mov> <t> <out.png>")
    }
    let before = try await frame(URL(fileURLWithPath: args[0]), at: tb)
    let after = try await frame(URL(fileURLWithPath: args[2]), at: ta)
    let crop = cropRect(full: CGSize(width: before.width, height: before.height))
    let width = Int(crop.width), panel = Int(crop.height)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: panel * 2, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0),
        let ctx = NSGraphicsContext(bitmapImageRep: rep)
    else { fail("could not create bitmap") }
    let flipped = NSGraphicsContext(cgContext: ctx.cgContext, flipped: true)
    NSGraphicsContext.current = flipped
    let cg = ctx.cgContext
    for (index, image) in [before, after].enumerated() {
        guard let cropped = image.cropping(to: crop) else { fail("crop outside the frame") }
        // CGContext.draw uses an unflipped coordinate space, so place panels from the bottom.
        let y = CGFloat(panel) * CGFloat(1 - index)
        cg.draw(cropped, in: CGRect(x: 0, y: y, width: CGFloat(width), height: CGFloat(panel)))
    }
    // Labels are drawn with AppKit in flipped coordinates.
    cg.saveGState()
    cg.translateBy(x: 0, y: CGFloat(panel * 2))
    cg.scaleBy(x: 1, y: -1)
    drawLabel(beforeLabel, panelTop: 0)
    drawLabel(afterLabel, panelTop: CGFloat(panel))
    cg.restoreGState()
    NSGraphicsContext.current = nil
    guard let png = rep.representation(using: .png, properties: [:]) else { fail("png encode failed") }
    try png.write(to: URL(fileURLWithPath: args[4]))
    print("\(args[4]) \(width)x\(panel * 2)")
}

// MARK: video

/// The label pill rendered to an image (CATextLayer text doesn't show up in exported video).
func labelImage(_ text: String) -> CGImage {
    let size = pillSize(text)
    let image = NSImage(size: size, flipped: true) { _ in
        drawLabel(text, panelTop: -labelInset.y, origin: .zero)
        return true
    }
    var rect = CGRect(origin: .zero, size: size)
    return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)!
}

func labelLayer(_ text: String, topLeft: CGPoint) -> CALayer {
    // Core Animation export space: origin bottom-left. `topLeft` is the pill's top-left corner.
    let size = pillSize(text)
    let pill = CALayer()
    pill.frame = CGRect(x: topLeft.x, y: topLeft.y - size.height, width: size.width, height: size.height)
    pill.contents = labelImage(text)
    return pill
}

func video(_ args: [String]) async throws {
    guard args.count == 6, let sb = Double(args[1]), let sa = Double(args[3]), let length = Double(args[4])
    else { fail("compare video <before.mov> <start> <after.mov> <start> <seconds> <out.mp4>") }
    let composition = AVMutableComposition()
    var tracks: [AVMutableCompositionTrack] = []
    var naturalSize = CGSize.zero
    for (path, start) in [(args[0], sb), (args[2], sa)] {
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        guard let source = try await asset.loadTracks(withMediaType: .video).first,
            let track = composition.addMutableTrack(
                withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { fail("no video track in \(path)") }
        naturalSize = try await source.load(.naturalSize)
        try track.insertTimeRange(
            CMTimeRange(start: seconds(start), duration: seconds(length)), of: source, at: .zero)
        tracks.append(track)
    }
    let crop = cropRect(full: naturalSize)
    let render = CGSize(width: crop.width, height: crop.height * 2)

    let instruction = AVMutableVideoCompositionInstruction()
    instruction.timeRange = CMTimeRange(start: .zero, duration: seconds(length))
    instruction.layerInstructions = tracks.enumerated().map { index, track in
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        // Keep each clip inside its own panel.
        layer.setCropRectangle(crop, at: .zero)
        // Video composition space: origin top-left. Before on top, after below.
        layer.setTransform(
            CGAffineTransform(translationX: -crop.minX, y: -crop.minY + crop.height * CGFloat(index)),
            at: .zero)
        return layer
    }

    let parent = CALayer()
    parent.frame = CGRect(origin: .zero, size: render)
    let videoLayer = CALayer()
    videoLayer.frame = parent.frame
    parent.addSublayer(videoLayer)
    parent.addSublayer(labelLayer(beforeLabel, topLeft: CGPoint(x: labelInset.x, y: render.height - labelInset.y)))
    parent.addSublayer(labelLayer(afterLabel, topLeft: CGPoint(x: labelInset.x, y: crop.height - labelInset.y)))

    let videoComposition = AVMutableVideoComposition()
    videoComposition.renderSize = render
    videoComposition.frameDuration = CMTime(value: 1, timescale: 60)
    videoComposition.instructions = [instruction]
    videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
        postProcessingAsVideoLayer: videoLayer, in: parent)

    guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality)
    else { fail("no export session") }
    session.videoComposition = videoComposition
    let out = URL(fileURLWithPath: args[5])
    try? FileManager.default.removeItem(at: out)
    try await session.export(to: out, as: .mp4)
    print("\(args[5]) \(Int(render.width))x\(Int(render.height)) \(length)s")
}

// MARK: gif

func gif(_ args: [String]) async throws {
    guard args.count >= 2 else { fail("compare gif <in.mp4> <out.gif> [fps] [width]") }
    let fps = args.count > 2 ? Double(args[2]) ?? 10 : 10
    let width = args.count > 3 ? Double(args[3]) ?? 640 : 640
    let asset = AVURLAsset(url: URL(fileURLWithPath: args[0]))
    let duration = try await asset.load(.duration).seconds
    let generator = AVAssetImageGenerator(asset: asset)
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    generator.maximumSize = CGSize(width: width, height: 0)
    let count = Int(duration * fps)
    let times = (0..<count).map { seconds(Double($0) / fps) }
    guard let destination = CGImageDestinationCreateWithURL(
        URL(fileURLWithPath: args[1]) as CFURL, UTType.gif.identifier as CFString, count, nil)
    else { fail("could not create gif") }
    CGImageDestinationSetProperties(
        destination,
        [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    let frameProperties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1 / fps]] as CFDictionary
    for await result in generator.images(for: times) {
        CGImageDestinationAddImage(destination, try result.image, frameProperties)
    }
    guard CGImageDestinationFinalize(destination) else { fail("gif finalize failed") }
    print("\(args[1]) \(count) frames")
}

@main
struct Compare {
    static func main() async throws {
        let args = Array(CommandLine.arguments.dropFirst())
        switch args.first {
        case "still": try await still(Array(args.dropFirst()))
        case "video": try await video(Array(args.dropFirst()))
        case "gif": try await gif(Array(args.dropFirst()))
        default: fail("usage: compare still|video|gif ...")
        }
    }
}
