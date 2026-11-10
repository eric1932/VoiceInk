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
    /// A thin rim with a short halo, without the wide bloom.
    let subtle: Bool

    var animatableData: S.AnimatableData {
        get { shape.animatableData }
        set { shape.animatableData = newValue }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    /// Bloom, halo and rim settings. In light mode the wide bloom reads as a pink smudge on white
    /// backgrounds, so the light is kept tight to the edge there; dark mode keeps the full glow.
    private struct GlowStyle {
        let bloomWidth: CGFloat, bloomBlur: CGFloat, bloomOpacity: Double
        let haloWidth: CGFloat, haloBlur: CGFloat, haloOpacity: Double
        let rimWidth: CGFloat, rimOpacity: Double
    }

    private var style: GlowStyle {
        switch (colorScheme == .light, subtle) {
        case (true, false), (false, true):
            // Tight to the edge: the normal look in light mode, the subtle one in dark mode.
            GlowStyle(
                bloomWidth: 6, bloomBlur: 6, bloomOpacity: 0.12,
                haloWidth: 4, haloBlur: 4, haloOpacity: 0.5,
                rimWidth: 1.5, rimOpacity: 0.85)
        case (true, true):
            GlowStyle(
                bloomWidth: 0, bloomBlur: 0, bloomOpacity: 0,
                haloWidth: 3, haloBlur: 3, haloOpacity: 0.35,
                rimWidth: 1.5, rimOpacity: 0.85)
        case (false, false):
            GlowStyle(
                bloomWidth: 8, bloomBlur: 14, bloomOpacity: 0.35,
                haloWidth: 6, haloBlur: 8, haloOpacity: 0.9,
                rimWidth: 1.2, rimOpacity: 0.45)
        }
    }

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

    init(tone: RecorderGlowTone, shape: S, subtle: Bool = false) {
        self.tone = tone
        self.shape = shape
        self.subtle = subtle
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
        let style = style
        return Canvas { ctx, size in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: bleed, dy: bleed)
            let slices = lobeSlices(of: shape.path(in: rect), head: head)

            // Wide, faint bloom that fades out past the edge.
            if style.bloomOpacity > 0 {
                ctx.drawLayer { layer in
                    layer.addFilter(.blur(radius: style.bloomBlur))
                    layer.opacity = style.bloomOpacity
                    stroke(slices, in: &layer, color: color, lineWidth: style.bloomWidth)
                }
            }
            // Soft halo centered on the edge.
            ctx.drawLayer { layer in
                layer.addFilter(.blur(radius: style.haloBlur))
                layer.opacity = style.haloOpacity
                stroke(slices, in: &layer, color: color, lineWidth: style.haloWidth)
            }
            // Fine rim on the edge itself.
            ctx.drawLayer { layer in
                layer.opacity = style.rimOpacity
                stroke(slices, in: &layer, color: color, lineWidth: style.rimWidth)
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
