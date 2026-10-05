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
        // A replaced area never sends the exit the old one owed, so ask where the pointer really is.
        resyncHover()
    }

    /// Reports hover from the pointer's real position, not from the last enter or exit AppKit delivered.
    func resyncHover() {
        guard let window else { onHoverChange?(false); return }
        let point = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        onHoverChange?(visibleRect.contains(point))
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
    /// The button was activated in one go, by a caller that cannot press and hold it.
    var onToggle: (() -> Void)?
    /// The button offered alongside a failure was clicked.
    var onRecoveryAction: ((RecoveryAction) -> Void)?
    var onAttentionChange: ((Bool) -> Void)?

    /// Where the microphone's level is pulled from on the main actor, keeping redraws off the audio thread.
    private var levelSource: (@Sendable () -> Float)?
    private var levelTimer: Timer?
    /// Called once a recording's input has stayed below the floor long enough to tell the person.
    var onInputSilent: () -> Void = {}
    private var appearanceObserver: (any NSObjectProtocol)?

    private let panel: DockPanel
    private let hostingView: DockHostingView<DockView>
    private let model: DockViewModel
    private let notificationCenter: NotificationCenter
    private let visibleFrameProvider: (@MainActor () -> CGRect?)?
    private var screenParametersObserver: (any NSObjectProtocol)?
    private var anchor: DockAnchor
    private var panelSize: CGSize

    init(
        presentation: DockPresentation = DictationPresenter.dock(for: .idle),
        shortcut: String = "⌃⌥",
        anchor: DockAnchor = .bottomRight,
        notificationCenter: NotificationCenter = .default,
        visibleFrameProvider: (@MainActor () -> CGRect?)? = nil
    ) {
        let model = DockViewModel(
            presentation: presentation, shortcut: shortcut, anchor: anchor)
        // Empty until shown, so a button that is never put on screen never animates.
        model.isShown = false
        self.model = model
        self.anchor = anchor
        self.notificationCenter = notificationCenter
        self.visibleFrameProvider = visibleFrameProvider
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
            onToggle: { [weak self] in self?.onToggle?() },
            onRecovery: { [weak self] action in self?.onRecoveryAction?(action) },
            onAttentionChange: { [weak self] _ in
                guard let self else { return }
                self.onAttentionChange?(self.model.isEngaged)
            },
            onDesiredSize: { [weak self] size in self?.resize(to: size) })
        hostingView.onHoverChange = { [weak self] isHovering in
            guard let self else { return }
            self.model.isHovering = isHovering
            self.onAttentionChange?(self.model.isEngaged)
        }

        observeAppearance()
        screenParametersObserver = notificationCenter.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reposition() }
        }
        reposition()
    }

    isolated deinit {
        if let appearanceObserver { NSWorkspace.shared.notificationCenter.removeObserver(appearanceObserver) }
        if let screenParametersObserver { notificationCenter.removeObserver(screenParametersObserver) }
    }

    // MARK: - Lifecycle

    /// `orderFrontRegardless`, never `makeKeyAndOrderFront`, so the keyboard stays with the user's app.
    func show() {
        model.isShown = true
        if model.presentation.isRecording { startMetering() }
        reposition()
        panel.orderFrontRegardless()
    }

    /// Orders the panel out and empties it, since a hidden panel's timeline views keep waking the app.
    func hide() {
        panel.orderOut(nil)
        model.isShown = false
        stopMetering()
    }

    /// Whether the button is on screen.
    var isVisible: Bool { panel.isVisible }

    /// The panel's current frame, for placement checks.
    var frame: CGRect { panel.frame }

    /// Whether the button's view draws anything, which it does only while the panel is on screen.
    var drawsContent: Bool { model.isShown }

    /// Whether the microphone's level is being read for the meter.
    var isMetering: Bool { levelTimer != nil }

    /// The only way the button's appearance ever changes.
    func update(with presentation: DockPresentation) {
        model.show(presentation)
        // Started and stopped where the state is known, so a meter cannot outlive its recording.
        if presentation.isRecording, model.isShown { startMetering() } else { stopMetering() }
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
                guard let self, self.model.meter(levelSource()) else { return }
                self.onInputSilent()
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

    /// Whether the idle button collapses to a grip, as the view will next draw it.
    var shrinksToGrip: Bool { model.shrinksToGrip }

    /// Says which keys the keycap shows; the shortcut is configurable, so it cannot be fixed at construction.
    func setShortcut(_ shortcut: String) {
        model.shortcut = shortcut
    }

    /// Says why the shortcut cannot be heard in place of the keycap hint, or nil to show the keycap again.
    func setShortcutUnheard(_ reason: String?) {
        model.shortcutUnheard = reason
    }

    /// Keeps notice colours aligned with the system's current Increase Contrast setting.
    private func observeAppearance() {
        appearanceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.model.increasesContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
            }
        }
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
        if let visibleFrame = visibleFrameProvider?() { return visibleFrame }
        // With no screen to place against, staying put beats moving somewhere arbitrary.
        let screens = NSScreen.screens
        let panelScreen = panel.screen.flatMap { current in screens.first { $0 == current } }
        let mainScreen = NSScreen.main.flatMap { current in screens.first { $0 == current } }
        return (panelScreen ?? mainScreen ?? screens.first)?.visibleFrame ?? panel.frame
    }

    private func configurePanel() {
        panel.styleMask = [.nonactivatingPanel]
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.worksWhenModal = true
        panel.level = .statusBar
        // `orderOut` would otherwise block the main thread for the length of AppKit's fade.
        panel.animationBehavior = .none
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
