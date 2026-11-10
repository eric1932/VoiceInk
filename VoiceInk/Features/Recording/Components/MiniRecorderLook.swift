import SwiftUI

/// User-adjustable look of the mini recorder (Settings > Interface, shown for the Mini style).
enum MiniRecorderLook {
    /// Opacity of the dark layer under the glass. Lower shows more of the blur behind the
    /// recorder; higher keeps the text readable over bright content.
    static let defaultDarkness: Double = 0.7
    static let darknessRange: ClosedRange<Double> = 0.4...0.9
    /// Slider values this close to the default snap onto it, so it's easy to get back to.
    static let darknessSnapDistance: Double = 0.025
}

/// The light that travels around the recorder's outline.
enum MiniRecorderGlow: String, CaseIterable, Identifiable {
    /// No light; the record button still shows red while listening and blue when done.
    case off
    /// A thin rim with a short halo.
    case subtle
    /// Rim, halo and a wide bloom (in dark mode).
    case normal

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off: String(localized: "Off")
        case .subtle: String(localized: "Subtle")
        case .normal: String(localized: "Normal")
        }
    }
}
