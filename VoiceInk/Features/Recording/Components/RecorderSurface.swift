import AppKit
import SwiftUI

/// Translucent background for the mini recorder: Liquid Glass on macOS 26+, a behind-window
/// blur on older systems, and solid black when Reduce Transparency is on.
/// Follows the same approach as `AutoLearnSuggestionSurface`.
struct RecorderSurface<S: Shape>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let shape: S

    /// Light tint on the glass itself.
    private let tint = Color.black.opacity(0.25)
    /// Fixed dark layer inside the glass. Liquid Glass turns light over bright content, which
    /// washes out the white text and level row; this keeps the pill dark on any background
    /// (about #282828 at 60 %, like a HUD panel).
    private let scrim = Color(white: 0.157).opacity(0.6)

    /// Faint top-down highlight plus a hairline inner edge that give the surface a little depth.
    private var highlight: some View {
        shape
            .fill(
                LinearGradient(
                    colors: [Color.white.opacity(0.03), Color.clear],
                    startPoint: .top,
                    endPoint: UnitPoint(x: 0.5, y: 0.33)
                )
            )
            .overlay { shape.stroke(Color.white.opacity(0.08), lineWidth: 1) }
            .allowsHitTesting(false)
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color.black, in: shape)
        } else if #available(macOS 26.0, *) {
            content
                .background {
                    ZStack {
                        shape.fill(scrim)
                        highlight
                    }
                }
                .glassEffect(.regular.tint(tint), in: shape)
        } else {
            content.background {
                ZStack {
                    RecorderBackdrop()
                    scrim
                    highlight
                }
                .clipShape(shape)
                .allowsHitTesting(false)
            }
        }
    }
}

private struct RecorderBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// Two-layer drop shadow drawn only outside `shape`, so it never darkens the translucent
/// surface: a tight contact shadow at the edge plus a softer one that falls downward.
struct RecorderShadow<S: Shape>: View {
    let shape: S

    var body: some View {
        ZStack {
            shape
                .fill(Color.black)
                .shadow(color: .black.opacity(0.30), radius: 1.5, x: 0, y: 1)
            shape
                .fill(Color.black)
                .shadow(color: .black.opacity(0.22), radius: 10, x: 0, y: 6)
        }
        .mask {
            // Punch the shape itself out so only the shadow around it remains. The extra
            // stroke widens the cut by ~1 pt, so the black fill's anti-aliased edge can't
            // show as a hairline (visible on light backgrounds).
            Rectangle()
                .padding(-48)
                .overlay {
                    ZStack {
                        shape
                        shape.stroke(lineWidth: 2)
                    }
                    .blendMode(.destinationOut)
                }
                .compositingGroup()
        }
        .allowsHitTesting(false)
    }
}
