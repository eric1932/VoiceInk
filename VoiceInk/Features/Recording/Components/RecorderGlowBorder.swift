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
struct RecorderGlowBorder<S: InsettableShape>: View {
    let tone: RecorderGlowTone
    let shape: S

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Seconds per full lap of the outline.
    private let lapDuration: TimeInterval = 2.5
    /// Fraction of the outline the lobe covers.
    private let lobeLength: Double = 0.55
    /// The lobe is drawn as this many slices whose opacity rises and falls from tail to head.
    private let sliceCount = 10
    private let recordingColor = Color(red: 1.0, green: 0.40, blue: 0.32)  // #FF6652, coral red
    private let doneColor = Color(red: 0.04, green: 0.52, blue: 1.0)  // #0A84FF

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
        .allowsHitTesting(false)
    }

    /// Position of the lobe's head along the outline, 0..<1.
    private func lapPosition(at date: Date) -> Double {
        guard !reduceMotion else { return 0.3 }
        return date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: lapDuration) / lapDuration
    }

    private func glow(color: Color, head: Double) -> some View {
        ZStack {
            // Wide, faint bloom that fades out well past the edge.
            lobe(color: color, head: head, lineWidth: 8).compositingGroup().blur(radius: 14).opacity(0.35)
            // Soft halo centered on the edge, ~10 pt to each side.
            lobe(color: color, head: head, lineWidth: 6).compositingGroup().blur(radius: 8).opacity(0.9)
            // Dim, fine rim on the edge itself.
            lobe(color: color, head: head, lineWidth: 1.2).opacity(0.45)
        }
    }

    private func lobe(color: Color, head: Double, lineWidth: CGFloat) -> some View {
        ZStack {
            ForEach(0..<sliceCount, id: \.self) { index in
                let sliceLength = lobeLength / Double(sliceCount)
                let start = head - lobeLength + sliceLength * Double(index)
                let weight = pow(sin(.pi * (Double(index) + 0.5) / Double(sliceCount)), 1.2)
                OutlineSlice(base: shape, from: start, to: start + sliceLength)
                    .stroke(color.opacity(weight), style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
            }
        }
    }
}

/// A stretch of a shape's outline between two path fractions, wrapping around 0/1.
///
/// Only the base shape's own geometry (e.g. a corner radius) is animatable. The fractions are
/// deliberately not: they advance every frame anyway, and letting an enclosing animation (such
/// as the recorder's resize spring) interpolate them would swing the lobe backwards across 0/1.
private struct OutlineSlice<Base: Shape>: Shape {
    var base: Base
    let from: Double
    let to: Double

    var animatableData: Base.AnimatableData {
        get { base.animatableData }
        set { base.animatableData = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let outline = base.path(in: rect)
        let start = from - from.rounded(.down)
        let end = start + (to - from)
        if end <= 1 {
            return outline.trimmedPath(from: start, to: end)
        }
        var path = outline.trimmedPath(from: start, to: 1)
        path.addPath(outline.trimmedPath(from: 0, to: end - 1))
        return path
    }
}
