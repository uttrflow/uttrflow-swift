import AppKit
import SwiftUI
import UttrflowContext
import UttrflowPredict
import UttrflowUX

/// The spinner drawn at the caret while the suggestion model is on its first load, where its answer would go.
@MainActor
final class SuggestionWarmUp {
    static let shared = SuggestionWarmUp()

    /// What VoiceOver is told the spinner is.
    static let label = "AI suggestions are loading."
    /// The spinner's side, which is the small control size.
    static let side: CGFloat = 16

    /// Whether the model is on its first load, when a line it would have answered shows the spinner.
    private(set) var isWarmingUp = false
    /// Whether the model has loaded since the feature was last turned on, which tells a first load from a reload.
    private var hasLoaded = false
    /// Whether the spinner is on screen.
    private(set) var isShowing = false
    /// Brings the panel forward without taking the keyboard; a test swaps it.
    var frontWindow: @MainActor (NSWindow) -> Void = { $0.orderFrontRegardless() }
    let panel: SuggestionPanel

    init() {
        panel = SuggestionPanel(
            contentRect: CGRect(x: 0, y: 0, width: Self.side, height: Self.side),
            styleMask: [.nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.hasShadow = false
        panel.animationBehavior = .none
        PrivateWindowSharing.apply(to: panel)
        panel.contentView = NSHostingView(rootView: SuggestionWarmUpView())
    }

    /// Follows the model's readiness: only the load before its first ready since the feature was turned on counts.
    func modelIs(_ readiness: SuggestionModelReadiness) {
        if readiness == .ready { hasLoaded = true }
        if readiness == .notAsked { hasLoaded = false }
        isWarmingUp = readiness == .loading && !hasLoaded
        if !isWarmingUp { hide() }
    }

    /// Whether a line the model would have answered is left silent only because the model is still on its first load.
    static func waits(
        after update: SuggestionUpdate, hasGenerator: Bool, isReady: Bool, isWarmingUp: Bool
    ) -> Bool {
        isWarmingUp && !isReady && update.suggestion == .silent
            && ModelPass.shouldAsk(after: update, hasGenerator: hasGenerator, isReady: true)
    }

    /// Shows the spinner at the caret of a field that would hold a ghost when the turn drew nothing for want of the model, and hides it otherwise.
    func settled(
        _ update: SuggestionUpdate, hasGenerator: Bool, isReady: Bool, blocked: Bool,
        in snapshot: FocusedFieldSnapshot
    ) {
        guard
            !blocked,
            Self.waits(after: update, hasGenerator: hasGenerator, isReady: isReady, isWarmingUp: isWarmingUp),
            snapshot.placement == .inlineGhost, let caret = snapshot.caret
        else { return hide() }
        show(at: caret, direction: snapshot.writingDirection == .rightToLeft ? .rightToLeft : .leftToRight)
    }

    /// Draws the spinner just past the caret, on the side the line runs; it offers nothing, so it claims no key.
    func show(at caret: CGRect, direction: WritingDirection) {
        let x = direction == .rightToLeft ? caret.minX - Self.side : caret.maxX
        panel.setFrame(
            CGRect(x: x, y: caret.midY - Self.side / 2, width: Self.side, height: Self.side), display: true)
        if !isShowing || !panel.isVisible { frontWindow(panel) }
        isShowing = true
    }

    func hide() {
        guard isShowing else { return }
        isShowing = false
        panel.orderOut(nil)
    }
}

/// The small spinner itself, labelled for VoiceOver.
struct SuggestionWarmUpView: View {
    var body: some View {
        ProgressView()
            .controlSize(.small)
            .frame(width: SuggestionWarmUp.side, height: SuggestionWarmUp.side)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(SuggestionWarmUp.label)
    }
}

extension SuggestionCoordinator {
    /// Settles a turn the model was not asked about, then hands it to the spinner, which shows only while the model first loads.
    func settledWithoutModel(
        _ update: SuggestionUpdate, _ hasGenerator: Bool, _ isReady: Bool, in snapshot: FocusedFieldSnapshot,
        settle: (SuggestionUpdate, FocusedFieldSnapshot) -> Void
    ) {
        settle(update, snapshot)
        SuggestionWarmUp.shared.settled(
            update, hasGenerator: hasGenerator, isReady: isReady, blocked: isSecureInputBlocking,
            in: snapshot)
    }
}
