// Extracts frames from a clip and lays them out as labeled contact sheets.
//
//   frames <video.mov> <outPrefix> [fps=10] [start=0] [end=clip end] [columns=4] [perSheet=24]
//
// Writes <outPrefix>-sheet-01.png, -02.png, ... Each tile is labeled with its timestamp.
import AVFoundation
import AppKit

let a = CommandLine.arguments
guard a.count >= 3 else {
    print("usage: frames <video> <outPrefix> [fps] [start] [end] [columns] [perSheet]")
    exit(2)
}
let url = URL(fileURLWithPath: a[1])
let outPrefix = a[2]
let fps = a.count > 3 ? Double(a[3])! : 10
let start = a.count > 4 ? Double(a[4])! : 0
let columns = a.count > 6 ? Int(a[6])! : 4
let perSheet = a.count > 7 ? Int(a[7])! : 24

let asset = AVURLAsset(url: url)
let duration = CMTimeGetSeconds(asset.duration)
let end = a.count > 5 ? min(Double(a[5])!, duration) : duration

let generator = AVAssetImageGenerator(asset: asset)
generator.requestedTimeToleranceBefore = .zero
generator.requestedTimeToleranceAfter = .zero
generator.appliesPreferredTrackTransform = true
generator.maximumSize = CGSize(width: Double(ProcessInfo.processInfo.environment["MAXW"] ?? "720") ?? 720, height: 0)  // MAXW=1120 for full size

var times: [Double] = []
var t = start
while t <= end + 1e-6 {
    times.append(t)
    t += 1 / fps
}

var frames: [(Double, CGImage)] = []
for time in times {
    if let image = try? generator.copyCGImage(at: CMTime(seconds: time, preferredTimescale: 600), actualTime: nil) {
        frames.append((time, image))
    }
}
guard let first = frames.first?.1 else {
    print("no frames extracted")
    exit(1)
}

let tileW = first.width
let tileH = first.height
let labelH = 26
let gap = 6

func writeSheet(_ chunk: ArraySlice<(Double, CGImage)>, index: Int) {
    let rows = Int(ceil(Double(chunk.count) / Double(columns)))
    let width = columns * tileW + (columns + 1) * gap
    let height = rows * (tileH + labelH) + (rows + 1) * gap
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)
    else { return }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor(white: 0.12, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()

    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 18, weight: .medium),
        .foregroundColor: NSColor.white,
    ]
    for (i, (time, image)) in chunk.enumerated() {
        let col = i % columns
        let row = i / columns
        let x = gap + col * (tileW + gap)
        // AppKit origin is bottom-left; lay out rows top-down.
        let yTop = height - gap - row * (tileH + labelH + gap)
        let imageRect = NSRect(x: x, y: yTop - labelH - tileH, width: tileW, height: tileH)
        NSGraphicsContext.current?.cgContext.draw(image, in: imageRect)
        NSString(string: String(format: "t=%.2fs", time))
            .draw(at: NSPoint(x: x + 4, y: yTop - labelH + 4), withAttributes: attrs)
    }
    NSGraphicsContext.restoreGraphicsState()

    let path = String(format: "%@-sheet-%02d.png", outPrefix, index)
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    print(path)
}

var sheetIndex = 1
var offset = 0
while offset < frames.count {
    let chunk = frames[offset..<min(offset + perSheet, frames.count)]
    writeSheet(chunk, index: sheetIndex)
    sheetIndex += 1
    offset += perSheet
}
print(String(format: "frames=%d tile=%dx%d duration=%.2fs", frames.count, tileW, tileH, duration))
