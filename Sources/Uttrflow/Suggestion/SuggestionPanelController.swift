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
    /// The field's own rectangle, whose right edge a long ghost is cut at.
    var field: CGRect?
    var fieldPointSize: CGFloat?
    /// Where the arrow keys have put the highlight, and whether they have moved it at all.
    var selection: SuggestionSelection = .untouched
    /// The key that accepts in this field, so the hint drawn after the ghost is the key that works.
    var acceptKey: AcceptKey = .tab
    /// The field's own font family, so the ghost is set in the face the line is.
    var fontFamily: String?
    /// The field's own text colour, so the ghost reads against the field and not against Uttrflow's appearance.
    var textColor: TextColor?
}

/// Owns the panel the suggestion is drawn in, one for the whole process so no two ghosts are ever on screen.
@MainActor
final class SuggestionPanelController {
    /// The one panel every suggestion loop draws in, so a loop rebuilt by a settings change cannot leave a second one behind.
    static let shared = SuggestionPanelController()

    private let panel: SuggestionPanel
    private let hostingView: NSHostingView<SuggestionView>
    private var request = SuggestionRequest()
    private var panelSize = CGSize(width: 1, height: 1)
    private var appearanceObserver: (any NSObjectProtocol)?
    private var isActuallyShowing = false

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
        field: CGRect? = nil,
        fieldPointSize: CGFloat? = nil,
        selection: SuggestionSelection = .untouched,
        acceptKey: AcceptKey = .tab,
        fontFamily: String? = nil,
        textColor: TextColor? = nil
    ) {
        request = SuggestionRequest(
            suggestion: suggestion, typed: typed, placement: placement, caret: caret,
            window: window, field: field, fieldPointSize: fieldPointSize, selection: selection,
            acceptKey: acceptKey, fontFamily: fontFamily, textColor: textColor)
        render()
    }

    func hide() {
        // Already hidden and already drawn hidden: redrawing would change nothing and costs a screen lookup per key.
        if request.suggestion == .silent, !panel.isVisible, drawn.style == .hidden { return }
        request.suggestion = .silent
        render()
    }

    /// Whether a suggestion is on screen, which keeps the pause clock following the field.
    var isShowing: Bool { isActuallyShowing }

    /// Exposed so a probe or a test can read back what was actually configured.
    var window: NSPanel { panel }

    /// What the panel is drawing right now, which a test reads back.
    var drawn: SuggestionPresentation { hostingView.rootView.presentation }

    /// How many times the view has been replaced, so a test can see that a redundant hide changes nothing.
    private(set) var renders = 0

    /// Redraws from the last request, measuring the new content before the panel is placed so old and new are never on screen together.
    private func render() {
        // Nothing to place means no screen to look up.
        let room =
            request.suggestion == .silent
            ? nil
            : request.caret.flatMap {
                SuggestionGeometry.availableWidth(caret: $0, field: request.field, screen: visibleFrame)
            }
        let presentation = SuggestionPresentation(
            request.suggestion, typed: request.typed, selection: request.selection,
            fieldPointSize: request.fieldPointSize, appearance: Self.appearance(),
            acceptKey: request.acceptKey, fontFamily: request.fontFamily,
            fieldTextColor: request.textColor, maximumWidth: room)
        hostingView.rootView = SuggestionView(
            presentation: presentation,
            onDesiredSize: { [weak self] size in self?.resize(to: size) })
        renders += 1
        guard presentation.style != .hidden else {
            isActuallyShowing = false
            panel.orderOut(nil)
            return
        }
        let measured = hostingView.fittingSize
        if measured.width > 0, measured.height > 0 {
            panelSize = CGSize(width: measured.width.rounded(.up), height: measured.height.rounded(.up))
        }
        guard reposition() else {
            isActuallyShowing = false
            panel.orderOut(nil)
            return
        }
        // `orderFrontRegardless`, never `makeKeyAndOrderFront`: no keyboard is taken.
        panel.orderFrontRegardless()
        isActuallyShowing = true
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
        guard drawn.style != .hidden else {
            isActuallyShowing = false
            return
        }
        guard reposition() else {
            isActuallyShowing = false
            return panel.orderOut(nil)
        }
        panel.orderFrontRegardless()
        isActuallyShowing = true
    }

    /// Places the panel at the caret, or reports that there is nowhere on the line to draw it.
    @discardableResult
    private func reposition() -> Bool {
        guard
            let anchor = SuggestionGeometry.anchor(
                for: request.placement, caret: request.caret, window: request.window,
                field: request.field, screen: visibleFrame, size: panelSize)
        else { return false }
        panel.setFrame(anchor.frame, display: true)
        return true
    }

    /// The screen the caret is on, so a field on another display is drawn there and not against the panel's last screen.
    private var screenHoldingCaret: NSScreen? {
        guard let caret = request.caret else { return nil }
        return NSScreen.screens.first { $0.frame.contains(CGPoint(x: caret.minX, y: caret.midY)) }
    }

    private var visibleFrame: CGRect {
        // With no screen to place against, staying put beats moving somewhere arbitrary.
        (screenHoldingCaret ?? panel.screen ?? NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? panel.frame
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
        // `orderOut` waits out AppKit's fade on the main thread, which would stall every keystroke over a ghost.
        panel.animationBehavior = .none
        panel.contentView = hostingView
    }
}
