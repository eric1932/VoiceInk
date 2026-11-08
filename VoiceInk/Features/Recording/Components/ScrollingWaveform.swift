import SwiftUI

/// Recording level row: capsules in fixed positions whose heights stream from right to left.
/// The capsules themselves never move; each tick shifts the level values one slot to the left
/// and every capsule glides toward its new height, so speech reads as a smooth wave travelling
/// along the row without any sub-pixel scrolling shimmer. Silence is a short dash.
struct ScrollingWaveform: View {
    let audioMeterProvider: () -> AudioMeter
    let color: Color
    /// When false new samples are silent, so the row settles back to dashes.
    var isActive: Bool = true

    private let pitch: CGFloat = 8
    private let capsuleWidth: CGFloat = 4
    private let minHeight: CGFloat = 3
    private let maxHeight: CGFloat = 14
    private let rowHeight: CGFloat = 24
    /// Normalized meter value treated as silence (room noise stays a flat dash).
    private let noiseFloor: Double = 0.15
    /// Meter value that already reads as a full-height capsule.
    private let fullScale: Double = 0.7

    @State private var model = LevelRowModel()

    var body: some View {
        TimelineView(.animation) { context in  // every display frame (120 Hz on ProMotion)
            let heights = model.update(
                at: context.date,
                level: isActive ? level(from: audioMeterProvider()) : 0
            )

            Canvas { ctx, size in
                let fitting = Int((size.width - capsuleWidth) / pitch) + 1
                let slots = max(1, min(fitting, heights.count))
                let rowWidth = CGFloat(slots - 1) * pitch + capsuleWidth
                let originX = (size.width - rowWidth) / 2
                for slot in 0..<slots {
                    // Slot 0 holds the newest value and sits at the right end.
                    let height = minHeight + CGFloat(heights[slot]) * (maxHeight - minHeight)
                    let x = originX + CGFloat(slots - 1 - slot) * pitch
                    let rect = CGRect(
                        x: x, y: (size.height - height) / 2, width: capsuleWidth, height: height)
                    ctx.fill(
                        Path(roundedRect: rect, cornerRadius: min(capsuleWidth, height) / 2),
                        with: .color(color.opacity(0.7)))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: rowHeight)
    }

    /// Gate out room noise, then stretch the speech range to the full capsule height.
    /// (The recorder's meter is already smoothed, so no extra smoothing happens here.)
    private func level(from meter: AudioMeter) -> Double {
        let gated = (meter.averagePower - noiseFloor) / (fullScale - noiseFloor)
        return pow(max(0, min(1, gated)), 0.8)
    }
}

/// Shift register of levels (index 0 = newest, rightmost) plus the heights currently shown.
/// A reference type so the timeline can advance it while rendering without extra view updates.
private final class LevelRowModel {
    private static let slotCapacity = 48
    /// Values shift one slot left this often (30 per second).
    private let tickInterval: TimeInterval = 1.0 / 30
    /// Seconds for a peak to fall to ~37 %: bursts trail off over a few slots, so a syllable
    /// reads as one wider band instead of a single spike.
    private let releaseTime: TimeInterval = 0.12
    /// How fast a shown height may change, in full-scale units per second (~0.12 s full swing).
    private let slewRate: Double = 8

    private var targets = [Double](repeating: 0, count: slotCapacity)
    private var shown = [Double](repeating: 0, count: slotCapacity)
    private var lastFrame: Date?
    private var nextTick: Date?
    private var pendingPeak: Double = 0
    private var envelope: Double = 0
    private var lastPushed: Double = 0

    /// Advances to `date`, folding in the current `level`, and returns the shown heights (0...1).
    func update(at date: Date, level: Double) -> [Double] {
        pendingPeak = max(pendingPeak, level)
        guard let last = lastFrame, var tick = nextTick else {
            lastFrame = date
            nextTick = date.addingTimeInterval(tickInterval)
            return shown
        }
        let elapsed = min(date.timeIntervalSince(last), 0.25)
        lastFrame = date

        // Shift in one value per elapsed tick (bounded, so a long pause doesn't replay history).
        var ticks = 0
        while date >= tick && ticks < 8 {
            envelope = max(pendingPeak, envelope * exp(-tickInterval / releaseTime))
            pendingPeak = 0
            let pushed = 0.65 * envelope + 0.35 * lastPushed  // neighbours stay close
            lastPushed = pushed
            targets.insert(pushed, at: 0)
            targets.removeLast()
            tick.addTimeInterval(tickInterval)
            ticks += 1
        }
        if date >= tick { tick = date.addingTimeInterval(tickInterval) }
        nextTick = tick

        // Every capsule glides toward its slot's value instead of jumping.
        let maxStep = slewRate * elapsed
        for index in shown.indices {
            shown[index] += max(-maxStep, min(maxStep, targets[index] - shown[index]))
        }
        return shown
    }
}
