import AppKit
import UttrflowCore
import UttrflowPipeline
import SwiftUI

/// A window that never becomes the active one.
///
/// Both overrides matter: without them AppKit will happily make a floating panel key
/// the moment it is clicked, which would pull the caret out of whatever the user is
/// dictating into — the one thing this button must never do.
final class DockPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The panel's content, with the two things AppKit will not give a hosted view for free.
final class DockHostingView<Content: View>: NSHostingView<Content> {
    var onHoverChange: ((Bool) -> Void)?
    private var hoverTracking: NSTrackingArea?

    /// Without this the click that starts a dictation is swallowed as the click that
    /// merely brings a window forward — and since another app is always frontmost
    /// here, that would be every click.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        // `.activeAlways`, not the default: the pointer has to be noticed while some
        // other application owns the keyboard, which is the only time this is hovered.
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self)
        addTrackingArea(area)
        hoverTracking = area
    }

    override func mouseEntered(with event: NSEvent) { onHoverChange?(true) }
    override func mouseExited(with event: NSEvent) { onHoverChange?(false) }
}

/// Owns the floating button.
///
/// Everything the panel does is a consequence of one rule — it must never take focus —
/// which is why the configuration below is applied whole rather than assembled from
/// whatever each behaviour seems to need.
@MainActor
final class DockPanelController {
    /// The mouse went down on the button. The same thing as the shortcut going down.
    var onPressBegan: (() -> Void)?
    /// The mouse came back up, wherever it happens to be by then.
    var onPressEnded: (() -> Void)?
    /// The button offered alongside a failure was clicked.
    var onRecoveryAction: ((RecoveryAction) -> Void)?

    private let panel: DockPanel
    private let hostingView: DockHostingView<DockView>
    private let model: DockViewModel
    private var anchor: DockAnchor
    private var panelSize: CGSize

    init(
        presentation: DockPresentation = DictationPresenter.dock(for: .idle),
        shortcut: String = "⌥Space",
        anchor: DockAnchor = .bottomRight
    ) {
        let model = DockViewModel(
            presentation: presentation, shortcut: shortcut, anchor: anchor)
        self.model = model
        self.anchor = anchor
        self.panelSize = CGSize(
            width: DockMetrics.gripWidth + DockMetrics.gripHitPadding * 2,
            height: DockMetrics.gripHeight + DockMetrics.gripHitPadding * 2)

        hostingView = DockHostingView(rootView: DockView(model: model))
        panel = DockPanel(
            contentRect: CGRect(origin: .zero, size: panelSize),
            styleMask: [.nonactivatingPanel], backing: .buffered, defer: false)

        configurePanel()

        // Set after `self` exists so the callbacks can reach it; weakly, because the
        // view is owned by the panel which is owned by this controller.
        hostingView.rootView = DockView(
            model: model,
            onPressBegan: { [weak self] in self?.onPressBegan?() },
            onPressEnded: { [weak self] in self?.onPressEnded?() },
            onRecovery: { [weak self] action in self?.onRecoveryAction?(action) },
            onDesiredSize: { [weak self] size in self?.resize(to: size) })
        hostingView.onHoverChange = { [weak self] isHovering in
            self?.model.isHovering = isHovering
        }

        reposition()
    }

    // MARK: - Lifecycle

    /// `orderFrontRegardless`, never `makeKeyAndOrderFront`: the floating button must
    /// appear without taking the keyboard from whatever the user is typing in.
    func show() {
        reposition()
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    /// The only way the button's appearance ever changes.
    func update(with presentation: DockPresentation) {
        model.show(presentation)
    }

    func setAnchor(_ anchor: DockAnchor) {
        self.anchor = anchor
        model.anchor = anchor
        reposition()
    }

    /// Says which keys the button should show on its keycap.
    ///
    /// The shortcut is configurable, so the keycap cannot be settled once at
    /// construction: a button reading "⌥Space" beside a shortcut the user has since
    /// changed teaches them the wrong key every time they glance at it.
    /// Whether the idle button collapses to a grip. See ``DockViewModel/shrinksToGrip``.
    ///
    /// No resize here: the two forms are different sizes, and the view reports its own
    /// through `onDesiredSize` as soon as it redraws. Setting the size from here as well
    /// would be a second thing deciding how big the panel is.
    func setShrinksToGrip(_ shrinks: Bool) {
        model.shrinksToGrip = shrinks
    }

    func setShortcut(_ shortcut: String) {
        model.shortcut = shortcut
    }

    /// Where a dragged button lands. The point is in screen coordinates.
    func snapToAnchor(nearest point: CGPoint) {
        setAnchor(DockPlacement.nearestAnchor(to: point, in: visibleFrame))
    }

    /// Exposed so a probe or a test can read back what was actually configured.
    var window: NSPanel { panel }

    var currentAnchor: DockAnchor { anchor }

    // MARK: - Geometry

    /// The view measures itself and reports what it wants; the panel follows. Sizing
    /// the window to the content is what keeps the resting grip from claiming a
    /// pill-sized rectangle of the screen the pointer cannot click through.
    private func resize(to size: CGSize) {
        let wanted = CGSize(width: size.width.rounded(.up), height: size.height.rounded(.up))
        guard wanted.width > 0, wanted.height > 0, wanted != panelSize else { return }
        panelSize = wanted
        reposition()
    }

    private func reposition() {
        panel.setFrame(
            DockPlacement.frame(for: anchor, panelSize: panelSize, in: visibleFrame),
            display: true)
    }

    private var visibleFrame: CGRect {
        // With no screen to place against, staying put beats moving somewhere arbitrary.
        (panel.screen ?? NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? panel.frame
    }

    private func configurePanel() {
        panel.styleMask = [.nonactivatingPanel]
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.worksWhenModal = true
        panel.level = .statusBar
        panel.collectionBehavior = [
            .canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle,
        ]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.contentView = hostingView
    }
}
