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

    /// How loud the microphone is, asked for while a recording is open.
    ///
    /// A closure rather than a stored number because the meter has to be *pulled*: the
    /// microphone's own callback arrives on a real-time thread roughly every 85 ms, and
    /// letting it drive the window would put a redraw on the audio thread's critical
    /// path. Polling on the main actor instead keeps the two clocks apart.
    /// `@Sendable` because the timer's closure is: the value is read on the main run
    /// loop, but the closure that reads it is handed to Foundation, which makes no
    /// promise about where it keeps it. The capture engine is an actor, so the closure
    /// the application passes satisfies this without ceremony.
    private var levelSource: (@Sendable () -> Float)?
    private var levelTimer: Timer?

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
        // Started and stopped from the one place the state is already known, so a meter
        // cannot outlive the recording it was drawn for — which, since the panel stays
        // on screen after a dictation, would otherwise be a timer running for the rest
        // of the session.
        if presentation.isRecording { startMetering() } else { stopMetering() }
    }

    /// Says where to read the microphone's level from.
    func setLevelSource(_ source: (@Sendable () -> Float)?) {
        levelSource = source
    }

    /// Twenty times a second, which is chosen rather than inherited.
    ///
    /// The tap hands over 4096 frames at a time — about twelve blocks a second — so
    /// polling faster than this would resample the same number, and polling much slower
    /// would show a meter that steps. Sixty was never on the table: the level would be
    /// crossing a thread boundary three times for every value that actually changed.
    private static let meteringInterval: TimeInterval = 0.05

    private func startMetering() {
        guard levelTimer == nil, let levelSource else { return }
        let timer = Timer(timeInterval: Self.meteringInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.model.level = levelSource()
            }
        }
        // `.common`, not the default: a run loop tracking a mouse drag — which is what
        // dragging the button to another corner is — stops servicing default-mode
        // timers, and the meter would freeze for exactly as long as the drag.
        RunLoop.main.add(timer, forMode: .common)
        levelTimer = timer
    }

    private func stopMetering() {
        levelTimer?.invalidate()
        levelTimer = nil
        model.level = 0
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
        // AppKit draws its own shadow around a transparent panel's opaque content, and
        // every form here already carries the one the design asks for. Two shadows around
        // a nine-point grip is what made the resting button look like a box with a black
        // border: the window's ring outside the slab's own.
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.contentView = hostingView
    }
}
