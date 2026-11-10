import SwiftUI

/// Look options for the mini recorder. Shown under "Recorder Style" when Mini is selected.
struct MiniRecorderLookSettings: View {
    @AppStorage(RecorderDisplaySettingsKeys.miniBackgroundDarkness)
    private var darkness = MiniRecorderLook.defaultDarkness
    @AppStorage(RecorderDisplaySettingsKeys.miniGlow) private var glow: MiniRecorderGlow = .normal

    /// Values near the default land exactly on it, so dragging back to the tick mark snaps.
    private var snappingDarkness: Binding<Double> {
        Binding(
            get: { darkness },
            set: { value in
                let isNearDefault =
                    abs(value - MiniRecorderLook.defaultDarkness) < MiniRecorderLook.darknessSnapDistance
                darkness = isNearDefault ? MiniRecorderLook.defaultDarkness : value
            }
        )
    }

    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                darknessSlider
                Text(verbatim: "\(Int((darkness * 100).rounded()))%")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .trailing)
            }
        } label: {
            HStack(spacing: 4) {
                Text("Recorder Background")
                InfoTip("How dark the recorder is behind its text. Lower shows more of the blur; higher reads better over bright windows. The tick marks the default (70%).")
            }
        }

        Picker("Recorder Glow", selection: $glow) {
            ForEach(MiniRecorderGlow.allCases) { option in
                Text(option.displayName).tag(option)
            }
        }
        .pickerStyle(.menu)
    }

    @ViewBuilder
    private var darknessSlider: some View {
        if #available(macOS 26.0, *) {
            Slider(value: snappingDarkness, in: MiniRecorderLook.darknessRange) {
                Text("Recorder Background")
            } ticks: {
                SliderTick(MiniRecorderLook.defaultDarkness)
            }
            .labelsHidden()
        } else {
            Slider(value: snappingDarkness, in: MiniRecorderLook.darknessRange) {
                Text("Recorder Background")
            }
            .labelsHidden()
        }
    }
}
