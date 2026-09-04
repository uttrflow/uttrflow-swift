import AppKit
import SwiftUI
import UttrflowContext
import UttrflowPredict
import UttrflowUX

/// A window that never becomes the active one, so the caret stays in the field under it.
final class SuggestionPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// What the surface was last asked to draw, so a display setting can change under it.
private struct SuggestionRequest {
    var suggestion: Suggestion = .silent
    /// What is already in the field, so the surface offers only what the suggestion adds.
    var typed: String = ""
    var placement: SuggestionPlacement = .inlineGhost
    var caret: CGRect?
    var window: CGRect?
    var fieldPointSize: CGFloat?
    /// Where the arrow keys have put the highlight, and whether they have moved it at all.
    var selection: SuggestionSelection = .untouched
    /// The key that accepts in this field, so the hint drawn after the ghost is the key that works.
    var acceptKey: AcceptKey = .tab
}

/// Owns the panel the suggestion is drawn in.
@MainActor
final class SuggestionPanelController {
    private let panel: SuggestionPanel
    private let hostingView: NSHostingView<SuggestionView>
    private var request = SuggestionRequest()
    private var panelSize = CGSize(width: 1, height: 1)
    private var appearanceObserver: (any NSObjectProtocol)?

    init() {
        hostingView = NSHostingView(rootView: SuggestionView(presentation: .init(.silent)))
        panel = SuggestionPanel(
            contentRect: CGRect(origin: .zero, size: panelSize),
            styleMask: [.nonactivatingPanel], backing: .buffered, defer: false)
        configurePanel()
        hostingView.rootView = SuggestionView(
            presentation: SuggestionPresentation(.silent),
            onDesiredSize: { [weak self] size in self?.resize(to: size) })
        observeAppearance()
    }

    isolated deinit {
        guard let appearanceObserver else { return }
        NSWorkspace.shared.notificationCenter.removeObserver(appearanceObserver)
    }

    /// Says what to draw and what to draw it against; `.silent` takes the surface away.
    func show(
        _ suggestion: Suggestion,
        typed: String = "",
        placement: SuggestionPlacement,
        caret: CGRect? = nil,
        window: CGRect? = nil,
        fieldPointSize: CGFloat? = nil,
        selection: SuggestionSelection = .untouched,
        acceptKey: AcceptKey = .tab
    ) {
        request = SuggestionRequest(
            suggestion: suggestion, typed: typed, placement: placement, caret: caret,
            window: window, fieldPointSize: fieldPointSize, selection: selection, acceptKey: acceptKey)
        render()
    }

    func hide() {
        request.suggestion = .silent
        render()
    }

    /// Exposed so a probe or a test can read back what was actually configured.
    var window: NSPanel { panel }

    /// Redraws from the last request and this Mac's current display settings.
    private func render() {
        let presentation = SuggestionPresentation(
            request.suggestion, typed: request.typed, selection: request.selection,
            fieldPointSize: request.fieldPointSize, appearance: Self.appearance(),
            acceptKey: request.acceptKey)
        hostingView.rootView = SuggestionView(
            presentation: presentation,
            onDesiredSize: { [weak self] size in self?.resize(to: size) })
        guard presentation.style != .hidden, reposition() else {
            panel.orderOut(nil)
            return
        }
        // `orderFrontRegardless`, never `makeKeyAndOrderFront`: no keyboard is taken.
        panel.orderFrontRegardless()
    }

    /// What Increase Contrast, Reduce Transparency and Reduce Motion are set to right now.
    private static func appearance() -> SuggestionAppearance {
        let workspace = NSWorkspace.shared
        return SuggestionAppearance(
            increasesContrast: workspace.accessibilityDisplayShouldIncreaseContrast,
            reducesTransparency: workspace.accessibilityDisplayShouldReduceTransparency,
            reducesMotion: workspace.accessibilityDisplayShouldReduceMotion)
    }

    /// Redraws when the user changes a display setting while the surface is on screen.
    private func observeAppearance() {
        appearanceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.render() }
        }
    }

    /// The view measures itself and reports what it wants; the panel follows and stays on screen.
    private func resize(to size: CGSize) {
        let wanted = CGSize(width: size.width.rounded(.up), height: size.height.rounded(.up))
        guard wanted.width > 0, wanted.height > 0, wanted != panelSize else { return }
        panelSize = wanted
        guard reposition() else { return }
        panel.orderFrontRegardless()
    }

    /// Places the panel at the caret, or reports that there is nowhere on the line to draw it.
    @discardableResult
    private func reposition() -> Bool {
        guard
            let anchor = SuggestionGeometry.anchor(
                for: request.placement, caret: request.caret, window: request.window,
                screen: visibleFrame, size: panelSize)
        else { return false }
        panel.setFrame(anchor.frame, display: true)
        return true
    }

    private var visibleFrame: CGRect {
        // With no screen to place against, staying put beats moving somewhere arbitrary.
        (panel.screen ?? NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? panel.frame
    }

    private func configurePanel() {
        panel.styleMask = [.nonactivatingPanel]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.worksWhenModal = true
        panel.level = .statusBar
        panel.collectionBehavior = [
            .canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle,
        ]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // Nothing here is clickable — Tab takes the suggestion — so clicks pass through to the field.
        panel.ignoresMouseEvents = true
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.hasShadow = false
        panel.contentView = hostingView
    }
}
