import AppKit
import SwiftUI
import os

@MainActor
class MiniWindowManager {
    private var windowController: NSWindowController?
    private var panel: MiniRecorderPanel?
    private var exit: MiniRecorderExit?
    private var pendingTeardown: Task<Void, Never>?
    /// How long a hidden panel stays up so the view's exit animation can finish.
    private let exitDuration: Duration = .milliseconds(800)

    private let makeView: (MiniRecorderExit) -> AnyView
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "MiniWindowManager")

    init(
        engine: VoiceInkEngine,
        recorder: Recorder,
        assistantSession: AssistantSession,
        onRecordButtonTapped: @escaping () -> Void,
        onCloseTapped: @escaping () -> Void,
        onAssistantFollowUp: @escaping (String) -> Void
    ) {
        self.makeView = { exit in
            AnyView(
                MiniRecorderView(
                    stateProvider: engine,
                    recorder: recorder,
                    assistantSession: assistantSession,
                    exit: exit,
                    onRecordButtonTapped: onRecordButtonTapped,
                    onCloseTapped: onCloseTapped,
                    onAssistantFollowUp: onAssistantFollowUp
                )
            )
        }
    }

    /// Builds a fresh panel whenever one is not already on screen.
    ///
    /// The panel and its hosting view used to be created once and then reused for the whole
    /// lifetime of the app, so a window that stopped rendering — after a sleep/wake cycle, a
    /// display reconfiguration, or any other WindowServer hiccup — kept swallowing every later
    /// `orderFrontRegardless()`, and only relaunching VoiceInk brought the recorder back.
    /// A window in that state still reports `isVisible == true` with a sane frame, so there is
    /// nothing reliable to test for from inside the process. Rebuilding unconditionally removes
    /// the question: a stale window can never survive into a second dictation. The cost is one
    /// NSPanel plus one hosting controller per dictation, which is noise next to starting audio
    /// capture and a transcription session in the same code path.
    @discardableResult
    func show(on screen: NSScreen? = nil) -> Bool {
        if pendingTeardown != nil {
            // The previous dictation's panel is still playing its exit; drop it now so the new
            // dictation still gets a fresh panel.
            cancelPendingTeardown()
            deinitializeWindow()
        }
        if panel == nil { initializeWindow(on: screen) }
        guard let panel else { return false }
        return panel.show(on: screen)
    }

    /// Tears the window down rather than just ordering it out, so `isVisible` is never used as a
    /// liveness test and no panel is carried across dictations. The teardown waits
    /// `exitDuration` so the view can animate out first.
    func hide() {
        guard let exit, pendingTeardown == nil else { return }
        exit.isExiting = true
        pendingTeardown = Task { @MainActor [weak self, exitDuration] in
            try? await Task.sleep(for: exitDuration)
            guard !Task.isCancelled, let self else { return }
            self.pendingTeardown = nil
            self.deinitializeWindow()
        }
    }

    func destroyWindow() {
        cancelPendingTeardown()
        deinitializeWindow()
    }

    private func cancelPendingTeardown() {
        pendingTeardown?.cancel()
        pendingTeardown = nil
    }

    // Rebuilding gives the SwiftUI content a new identity, so view-local state inside it is
    // reset — currently the assistant follow-up draft and its focus. The conversation itself
    // lives in `AssistantSession`, which is owned by the engine and survives.
    private func initializeWindow(on screen: NSScreen?) {
        deinitializeWindow()
        guard let metrics = MiniRecorderPanel.calculateWindowMetrics(screen: screen) else {
            logger.error("Mini panel not created: no screen available")
            return
        }
        let newPanel = MiniRecorderPanel(contentRect: metrics)
        let newExit = MiniRecorderExit()
        let view = makeView(newExit)
        let hostingController = NSHostingController(rootView: view)
        newPanel.contentView = hostingController.view
        panel = newPanel
        exit = newExit
        windowController = NSWindowController(window: newPanel)
    }

    private func deinitializeWindow() {
        panel?.orderOut(nil)
        windowController?.close()
        windowController = nil
        panel = nil
        exit = nil
    }
}

/// Tells the mini recorder view that its panel is about to be torn down, so it can animate out.
@MainActor
final class MiniRecorderExit: ObservableObject {
    @Published var isExiting = false
}
