import SwiftUI

struct MiniRecorderView<S: RecorderStateProvider & ObservableObject>: View {
    @ObservedObject var stateProvider: S
    @ObservedObject var recorder: Recorder
    @ObservedObject var assistantSession: AssistantSession
    @ObservedObject var exit: MiniRecorderExit
    let onRecordButtonTapped: () -> Void
    let onCloseTapped: () -> Void
    let onAssistantFollowUp: (String) -> Void
    @AppStorage(RecorderDisplaySettingsKeys.showLiveTranscript) private var showLiveTranscript = true
    @AppStorage(RecorderDisplaySettingsKeys.miniBackgroundDarkness)
    private var backgroundDarkness = MiniRecorderLook.defaultDarkness
    @AppStorage(RecorderDisplaySettingsKeys.miniGlow) private var glow: MiniRecorderGlow = .normal

    // Visual-only state: keeps the last live text and the "done" look on screen while the
    // panel animates out, since the engine clears the text as soon as recording stops.
    @State private var heldTranscript = ""
    @State private var didProcess = false
    @State private var hasAppeared = false

    // MARK: - Layout Constants

    private let controlBarHeight: CGFloat = 40
    private let compactWidth: CGFloat = 184
    private let expandedWidth: CGFloat = 300
    private let assistantWidth: CGFloat = 520
    private let compactCornerRadius: CGFloat = 20
    private let expandedCornerRadius: CGFloat = 14
    /// Room below the recorder so its shadow isn't cut off by the panel edge.
    private let shadowMargin: CGFloat = 24

    /// Expanding from the compact pill when text first arrives, and collapsing back.
    private let resizeAnimation = Animation.spring(response: 0.4, dampingFraction: 0.85)
    /// Growing or shrinking by one line of text; a touch softer than the expand.
    private let lineChangeAnimation = Animation.spring(response: 0.45, dampingFraction: 0.9)
    private let appearAnimation = Animation.easeOut(duration: 0.22)
    /// Seconds the finished recorder stays on screen (in its "done" color) before fading.
    private let doneHold: Double = 0.5

    private var shape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: hasLiveTranscript || hasAssistantResponse ? expandedCornerRadius : compactCornerRadius,
            style: .continuous)
    }

    private var isProcessing: Bool {
        stateProvider.recordingState == .transcribing || stateProvider.recordingState == .enhancing
    }

    /// Processing finished normally (not a cancel) and the panel is about to be dismissed.
    /// Doesn't wait for `exit.isExiting`: the engine goes idle a moment before it hides the panel.
    private var isFinishing: Bool {
        didProcess && stateProvider.recordingState == .idle && !hasAssistantResponse
    }

    private var transcriptText: String {
        stateProvider.recordingState == .recording ? stateProvider.partialTranscript : heldTranscript
    }

    // true while live transcript is streaming in, and while the finished text is held on screen
    private var hasLiveTranscript: Bool {
        guard showLiveTranscript, !transcriptText.isEmpty else { return false }
        return stateProvider.recordingState == .recording || isProcessing || isFinishing
    }

    private var glowTone: RecorderGlowTone {
        if glow == .off { return .none }
        if stateProvider.recordingState == .recording { return .recording }
        if isProcessing || isFinishing { return .done }
        return .none
    }

    private var isOnScreen: Bool { hasAppeared && !exit.isExiting }

    private var hasAssistantResponse: Bool {
        assistantSession.isVisible
    }

    private var shouldShowCloseButton: Bool {
        hasAssistantResponse && stateProvider.recordingState == .idle && !assistantSession.isBusy
    }

    private var liveAssistantFollowUpText: String {
        guard showLiveTranscript, stateProvider.recordingState == .recording else { return "" }
        return stateProvider.partialTranscript
    }

    private var controlBar: some View {
        HStack(spacing: 0) {
            Group {
                if shouldShowCloseButton {
                    RecorderCloseButton(action: onCloseTapped)
                } else {
                    RecorderRecordButton(
                        // Keep the processing spinner through the exit hold instead of
                        // flashing back to the idle look.
                        recordingState: isFinishing ? .transcribing : stateProvider.recordingState,
                        // Same coral as the glow, so there's one red on screen, not two.
                        recordingTint: Color(red: 1.0, green: 0.42, blue: 0.37),  // #FF6B5E
                        processingTint: Color(red: 0.04, green: 0.52, blue: 1.0),
                        action: onRecordButtonTapped
                    )
                }
            }
            .padding(.leading, 16)

            Spacer(minLength: 0)

            RecorderStatusDisplay(
                currentState: stateProvider.recordingState,
                audioMeterProvider: recorder.audioMeterSnapshot,
                scrollingWaveform: true
            )
            .padding(.horizontal, 12)

            Spacer(minLength: 0)

            RecorderModeButton(
                buttonSize: 22,
                padding: EdgeInsets()
            )
            .padding(.trailing, 12)
        }
        .frame(height: controlBarHeight)
    }

    private var transcriptSection: some View {
        VStack(spacing: 0) {
            if hasLiveTranscript {
                MiniTranscriptText(text: transcriptText, resize: lineChangeAnimation)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .offset(y: 6)))
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if hasAssistantResponse {
                AssistantPanelView(
                    session: assistantSession,
                    liveFollowUpText: liveAssistantFollowUpText,
                    onSend: onAssistantFollowUp
                )
                Divider().background(Color.white.opacity(0.15))
            } else {
                transcriptSection
            }
            controlBar
        }
        .frame(width: hasAssistantResponse ? assistantWidth : (hasLiveTranscript ? expandedWidth : compactWidth))
        .modifier(RecorderSurface(shape: shape, darkness: backgroundDarkness))
        .clipShape(shape)
        .overlay { RecorderGlowBorder(tone: glowTone, shape: shape, subtle: glow == .subtle) }
        .background { RecorderShadow(shape: shape) }
        .opacity(isOnScreen ? 1 : 0)
        .scaleEffect(isOnScreen ? 1 : (exit.isExiting ? 0.97 : 0.96), anchor: .bottom)
        .animation(appearAnimation, value: hasAppeared)
        .animation(.easeIn(duration: 0.2).delay(isFinishing ? doneHold : 0), value: exit.isExiting)
        .onAppear { hasAppeared = true }
        .onChange(of: stateProvider.partialTranscript) { _, text in
            if !text.isEmpty { heldTranscript = text }
        }
        .onChange(of: stateProvider.recordingState) { _, state in
            if state == .transcribing || state == .enhancing { didProcess = true }
            if state == .starting || state == .recording { didProcess = false }
        }
        .gesture(WindowDragGesture())
        .allowsWindowActivationEvents()
        .padding(.bottom, shadowMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        // Outermost, so the resize also animates the pill's centered position: it grows out
        // from the middle and upward, instead of jumping left and growing to the right.
        .animation(resizeAnimation, value: hasLiveTranscript)
        .animation(resizeAnimation, value: hasAssistantResponse)
    }
}
