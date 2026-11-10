import AppKit
import SwiftUI

enum RecorderGlowTone: Equatable {
    case none
    /// Listening: warm coral red.
    case recording
    /// Transcribing / enhancing / just finished: cool blue.
    case done
}

/// A soft lobe of light that travels clockwise along the recorder's outline at constant speed.
/// Purely visual; the caller maps the recording state to a tone.
///
/// Only the shape's own geometry (its corner radius) is animatable, so the recorder's resize
/// spring morphs the outline smoothly. The lobe's position comes straight from the clock and is
/// never interpolated: an enclosing animation would otherwise swing it backwards across 0/1.
struct RecorderGlowBorder<S: InsettableShape>: View, Animatable {
    let tone: RecorderGlowTone
    var shape: S

    var animatableData: S.AnimatableData {
        get { shape.animatableData }
        set { shape.animatableData = newValue }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Seconds per full lap of the outline.
    private let lapDuration: TimeInterval = 2.5
    /// Fraction of the outline the lobe covers.
    private let lobeLength: Double = 0.55
    /// Slices the lobe is drawn with; enough that the brightness falloff has no visible steps.
    private let sliceCount = 48
    /// Room around the outline for the halo and bloom, which spread past the edge.
    private let bleed: CGFloat = 24
    private let recordingColor = Color(red: 1.0, green: 0.40, blue: 0.32)  // #FF6652, coral red
    private let doneColor = Color(red: 0.04, green: 0.52, blue: 1.0)  // #0A84FF

    init(tone: RecorderGlowTone, shape: S) {
        self.tone = tone
        self.shape = shape
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: reduceMotion || tone == .none)) { context in
            let head = lapPosition(at: context.date)
            ZStack {
                // Red leaves first, then blue arrives, so the two never blend into mauve.
                glow(color: recordingColor, head: head)
                    .opacity(tone == .recording ? 1 : 0)
                    .animation(.easeOut(duration: 0.15), value: tone)
                glow(color: doneColor, head: head)
                    .opacity(tone == .done ? 1 : 0)
                    .animation(.easeIn(duration: 0.15).delay(tone == .done ? 0.15 : 0), value: tone)
            }
        }
        .padding(-bleed)
        .allowsHitTesting(false)
    }

    /// Position of the lobe's head along the outline, 0..<1.
    private func lapPosition(at date: Date) -> Double {
        guard !reduceMotion else { return 0.3 }
        return date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: lapDuration) / lapDuration
    }

    private func glow(color: Color, head: Double) -> some View {
        Canvas { ctx, size in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: bleed, dy: bleed)
            let slices = lobeSlices(of: shape.path(in: rect), head: head)

            // Wide, faint bloom that fades out well past the edge.
            ctx.drawLayer { layer in
                layer.addFilter(.blur(radius: 14))
                layer.opacity = 0.35
                stroke(slices, in: &layer, color: color, lineWidth: 8)
            }
            // Soft halo centered on the edge, ~10 pt to each side.
            ctx.drawLayer { layer in
                layer.addFilter(.blur(radius: 8))
                layer.opacity = 0.9
                stroke(slices, in: &layer, color: color, lineWidth: 6)
            }
            // Dim, fine rim on the edge itself.
            ctx.drawLayer { layer in
                layer.opacity = 0.45
                stroke(slices, in: &layer, color: color, lineWidth: 1.2)
            }
        }
    }

    /// The lobe as consecutive slices of the outline, each with its brightness on a smooth bell
    /// curve (dark at both ends, brightest in the middle).
    private func lobeSlices(of outline: Path, head: Double) -> [(path: Path, weight: Double)] {
        let sliceLength = lobeLength / Double(sliceCount)
        return (0..<sliceCount).map { index in
            let start = head - lobeLength + sliceLength * Double(index)
            let phase = (Double(index) + 0.5) / Double(sliceCount)
            let weight = pow(sin(.pi * phase), 2)
            return (outlineSegment(outline, from: start, length: sliceLength), weight)
        }
    }

    private func stroke(
        _ slices: [(path: Path, weight: Double)], in ctx: inout GraphicsContext, color: Color, lineWidth: CGFloat
    ) {
        let style = StrokeStyle(lineWidth: lineWidth, lineCap: .butt)
        for slice in slices {
            ctx.stroke(slice.path, with: .color(color.opacity(slice.weight)), style: style)
        }
    }

    /// A stretch of the outline starting at path fraction `from`, wrapping around 0/1.
    private func outlineSegment(_ outline: Path, from: Double, length: Double) -> Path {
        let start = from - from.rounded(.down)
        let end = start + length
        if end <= 1 {
            return outline.trimmedPath(from: start, to: end)
        }
        var path = outline.trimmedPath(from: start, to: 1)
        path.addPath(outline.trimmedPath(from: 0, to: end - 1))
        return path
    }
}
