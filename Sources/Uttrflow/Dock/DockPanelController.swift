// The non-activating panel that carries the floating button, and its metering timer.

import AppKit
import UttrflowCore
import UttrflowPipeline
import SwiftUI

/// A window that never becomes key or main, so a click on it cannot pull the caret out of another app.
final class DockPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The panel's content, with the two things AppKit will not give a hosted view for free.
final class DockHostingView<Content: View>: NSHostingView<Content> {
    var onHoverChange: ((Bool) -> Void)?
    private var hoverTracking: NSTrackingArea?

    /// Takes the first click; another app is always frontmost, so every click would otherwise be swallowed.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        // `.activeAlways`: the pointer must be noticed while another application owns the keyboard.
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

/// Owns the floating button; every line of its configuration follows from "never take focus".
@MainActor
final class DockPanelController {
    /// The mouse went down on the button. The same thing as the shortcut going down.
    var onPressBegan: (() -> Void)?
    /// The mouse came back up, wherever it happens to be by then.
    var onPressEnded: (() -> Void)?
    /// The button offered alongside a failure was clicked.
    var onRecoveryAction: ((RecoveryAction) -> Void)?

    /// Where the microphone's level is pulled from on the main actor, keeping redraws off the audio thread.
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

        // Set after `self` exists so the callbacks can reach it, weakly.
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

    /// `orderFrontRegardless`, never `makeKeyAndOrderFront`, so the keyboard stays with the user's app.
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
        // Started and stopped where the state is known, so a meter cannot outlive its recording.
        if presentation.isRecording { startMetering() } else { stopMetering() }
    }

    /// Says where to read the microphone's level from.
    func setLevelSource(_ source: (@Sendable () -> Float)?) {
        levelSource = source
    }

    /// Twenty times a second: the tap hands over about twelve blocks a second, so faster only resamples.
    private static let meteringInterval: TimeInterval = 0.05

    private func startMetering() {
        guard levelTimer == nil, let levelSource else { return }
        let timer = Timer(timeInterval: Self.meteringInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.model.meter(levelSource())
            }
        }
        // `.common`, so a drag of the button to another corner does not freeze the meter.
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

    /// Whether the idle button collapses to a grip; no resize here, because the view reports its own size.
    func setShrinksToGrip(_ shrinks: Bool) {
        model.shrinksToGrip = shrinks
    }

    /// Says which keys the keycap shows; the shortcut is configurable, so it cannot be fixed at construction.
    func setShortcut(_ shortcut: String) {
        model.shortcut = shortcut
    }

    // MARK: - Geometry

    /// Follows the size the view reports, so the resting grip claims no more of the screen than it draws.
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
        // AppKit's own shadow around the slab's shadow made the resting grip look boxed.
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.contentView = hostingView
    }
}
