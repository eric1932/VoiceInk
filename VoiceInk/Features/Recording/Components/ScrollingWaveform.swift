import SwiftUI

/// Recording level meter drawn as a row of capsules that streams from right to left: each new
/// level slides in on the right and drifts left. Silence is a short dash; loudness only makes a
/// capsule taller (one color, no flicker), which keeps the motion calm. Fills the width it's given.
struct ScrollingWaveform: View {
    let audioMeterProvider: () -> AudioMeter
    let color: Color
    /// When false new samples are silent, so the row settles back to dashes.
    var isActive: Bool = true

    /// Distance between capsule centers, which is also how far the row moves per sample.
    private let pitch: CGFloat = 8
    private let capsuleWidth: CGFloat = 4
    private let minHeight: CGFloat = 3
    private let maxHeight: CGFloat = 14
    private let rowHeight: CGFloat = 24
    /// Seconds between samples; the row scrolls at pitch / sampleInterval ≈ 110 pt/s.
    private let sampleInterval: TimeInterval = 0.073
    /// Normalized meter value treated as silence (room noise stays a flat dash).
    private let noiseFloor: Double = 0.15
    /// Meter value that already reads as a full-height capsule.
    private let fullScale: Double = 0.7

    @State private var history = LevelHistory()

    var body: some View {
        TimelineView(.animation) { context in  // every display frame (120 Hz on ProMotion)
            let progress = history.advance(
                to: context.date,
                interval: sampleInterval,
                level: isActive ? level(from: audioMeterProvider()) : 0
            )
            let levels = history.levels

            Canvas { ctx, size in
                let slots = Int(size.width / pitch) + 2
                for slot in 0..<slots {
                    // Slot 0 is the newest level, entering from just past the right edge.
                    let level = slot < levels.count ? levels[levels.count - 1 - slot] : 0
                    let centerX = size.width + pitch / 2 - (CGFloat(slot) + CGFloat(progress)) * pitch
                    guard centerX > -pitch, centerX < size.width + pitch else { continue }
                    let height = minHeight + CGFloat(level) * (maxHeight - minHeight)
                    let rect = CGRect(
                        x: centerX - capsuleWidth / 2, y: (size.height - height) / 2,
                        width: capsuleWidth, height: height)
                    ctx.fill(
                        Path(roundedRect: rect, cornerRadius: min(capsuleWidth, height) / 2),
                        with: .color(color.opacity(0.7)))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: rowHeight)
        .mask(edgeFade)
    }

    /// Gate out room noise, then stretch the speech range to the full capsule height.
    /// (The recorder's meter is already smoothed, so no extra smoothing happens here.)
    private func level(from meter: AudioMeter) -> Double {
        let gated = (meter.averagePower - noiseFloor) / (fullScale - noiseFloor)
        return pow(max(0, min(1, gated)), 0.8)
    }

    private var edgeFade: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0.0),
                .init(color: .black, location: 0.15),
                .init(color: .black, location: 0.90),
                .init(color: .clear, location: 1.0),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

/// Fixed-cadence history of levels. Each slot keeps the loudest level seen during its interval,
/// so syllable peaks aren't lost between samples. A reference type so the timeline can append
/// to it while rendering without triggering extra view updates.
private final class LevelHistory {
    private(set) var levels: [Double] = []
    private var lastSampleDate: Date?
    private var pendingPeak: Double = 0
    private let capacity = 160

    /// Appends a level whenever `interval` has passed and returns how far (0...1) the
    /// row has moved toward the next slot.
    func advance(to date: Date, interval: TimeInterval, level: Double) -> Double {
        pendingPeak = max(pendingPeak, level)
        guard let last = lastSampleDate else {
            lastSampleDate = date
            return 0
        }

        var elapsed = date.timeIntervalSince(last)
        if elapsed >= interval {
            let sample = pendingPeak
            pendingPeak = 0

            if elapsed >= interval * 8 {
                // Long gap (e.g. the view was off screen); restart the cadence from now.
                levels.append(sample)
                lastSampleDate = date
                elapsed = 0
            } else {
                // A late frame: keep the cadence and let the row catch up by the slots it
                // missed, instead of snapping it back (which reads as a stutter).
                let steps = (elapsed / interval).rounded(.down)
                levels.append(contentsOf: repeatElement(sample, count: Int(steps)))
                lastSampleDate = last.addingTimeInterval(steps * interval)
                elapsed -= steps * interval
            }

            if levels.count > capacity {
                levels.removeFirst(levels.count - capacity)
            }
        }
        return min(1, max(0, elapsed / interval))
    }
}
