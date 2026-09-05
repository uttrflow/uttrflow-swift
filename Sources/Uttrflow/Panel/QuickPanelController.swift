// The non-activating quick panel window, its resize border and its placement.

import AppKit
import UttrflowClipboard
import UttrflowUX
import SwiftUI

/// A non-activating panel that takes typing: key yes, main never. See Docs/app-quick-panel.md.
final class QuickPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// The panel's content, with the two things AppKit will not give a hosted view for free.
final class QuickPanelHostingView<Content: View>: NSHostingView<Content> {
    /// Takes the first click, because the application underneath stays frontmost and every click is a first.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Told after every step of a drag, so the controller does not read the resize back as a move.
    var onResize: ((CGRect) -> Void)?

    /// The frame and pointer when the drag began, held so clamping never makes the frame trail the pointer.
    private var drag: (edge: PanelEdge, frame: CGRect, pointer: CGPoint)?

    /// The border claims the click; everything inside it belongs to SwiftUI.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        if PanelResize.edge(at: local, in: bounds.size, isFlipped: isFlipped) != nil {
            return self
        }
        return super.hitTest(point)
    }

    /// Sets the resize cursors on the border, the only visible sign that a borderless window can be resized.
    override func resetCursorRects() {
        super.resetCursorRects()
        // The same bands the hit test uses, in this view's flipped coordinates.
        for (rect, edge) in PanelResize.borders(in: bounds.size, isFlipped: isFlipped) {
            addCursorRect(rect, cursor: .frameResize(position: edge.cursor, directions: .all))
        }
    }

    override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        guard let window,
            let edge = PanelResize.edge(at: local, in: bounds.size, isFlipped: isFlipped)
        else {
            super.mouseDown(with: event)
            return
        }
        drag = (edge, window.frame, NSEvent.mouseLocation)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let drag, let window else {
            super.mouseDragged(with: event)
            return
        }
        let now = NSEvent.mouseLocation
        let frame = PanelResize.resized(
            drag.frame, dragging: drag.edge,
            by: CGSize(width: now.x - drag.pointer.x, height: now.y - drag.pointer.y),
            within: window.screen?.visibleFrame)
        window.setFrame(frame, display: true)
        // The rects are in this view's coordinates and every one of them has just moved.
        window.invalidateCursorRects(for: self)
        onResize?(frame)
    }

    override func mouseUp(with event: NSEvent) {
        guard drag != nil else {
            super.mouseUp(with: event)
            return
        }
        drag = nil
    }
}

extension PanelEdge {
    /// The resize cursor for this border; `frameResize` has diagonals where `resizeLeftRight` does not.
    var cursor: NSCursor.FrameResizePosition {
        switch self {
        case .left: .left
        case .right: .right
        case .top: .top
        case .bottom: .bottom
        case .topLeft: .topLeft
        case .topRight: .topRight
        case .bottomLeft: .bottomLeft
        case .bottomRight: .bottomRight
        }
    }
}

/// Owns the quick panel: a window and a renderer, with the snapshot the keys apply to left to the app.
@MainActor
final class QuickPanelController: NSObject, NSWindowDelegate {
    /// A keystroke or its click, with the application that owned the caret when the panel opened.
    var onKey: ((PanelKey, NSRunningApplication?) -> Void)?

    /// A row action the panel cannot answer itself — copy, pin, unpin — for the store to carry out.
    var onIntent: ((PanelIntent) -> Void)?

    private let panel: QuickPanel
    private let hostingView: QuickPanelHostingView<QuickPanelView>
    private var presentation: PanelPresentation
    private var openCount = 0

    /// Whose caret this is. Captured on the way in, reported on the way out.
    private var caretOwner: NSRunningApplication?
    /// Live only while the panel is on screen; see ``watchForLeaving()``.
    private var clicks: Any?
    private var switching: (any NSObjectProtocol)?

    /// The origin `show(_:)` last set, compared in `windowDidMove` because AppKit reports that move late.
    private var placedOrigin: CGPoint?

    /// Where the user last dragged the panel; two keys, because the size is the design's and never restored.
    private static let originXKey = "com.uttrflow.panel.origin.x"
    private static let originYKey = "com.uttrflow.panel.origin.y"

    private var rememberedOrigin: CGPoint? {
        let defaults = UserDefaults.standard
        // `object(forKey:)`: `double(forKey:)` answers 0 for a key never written, and 0,0 is a real corner.
        guard defaults.object(forKey: Self.originXKey) != nil,
            defaults.object(forKey: Self.originYKey) != nil
        else { return nil }
        return CGPoint(
            x: defaults.double(forKey: Self.originXKey),
            y: defaults.double(forKey: Self.originYKey))
    }

    init(presentation: PanelPresentation = .placeholder) {
        self.presentation = presentation
        hostingView = QuickPanelHostingView(rootView: QuickPanelView(presentation: presentation))
        panel = QuickPanel(
            contentRect: CGRect(
                origin: .zero,
                size: CGSize(width: QuickPanelMetrics.width, height: QuickPanelMetrics.height)),
            styleMask: [.nonactivatingPanel], backing: .buffered, defer: false)

        super.init()
        configurePanel()
        // A left or bottom drag moves the origin too; claiming it keeps a resize from being remembered.
        hostingView.onResize = { [weak self] frame in self?.placedOrigin = frame.origin }
        draw()
    }

    // MARK: - Lifecycle

    /// Puts the panel on screen and makes it key without activating the application.
    func show(_ presentation: PanelPresentation) {
        // Recorded before the panel is ordered in, so the app is told where the clip belongs.
        caretOwner = NSWorkspace.shared.frontmostApplication

        openCount += 1
        self.presentation = presentation
        draw()

        let frame = placedFrame(on: Self.activeScreen())
        placedOrigin = frame.origin
        panel.setFrame(frame, display: false)
        panel.orderFrontRegardless()
        panel.makeKey()
        watchForLeaving()
    }

    /// Redraws an open panel after a key has been applied to the snapshot.
    func update(_ presentation: PanelPresentation) {
        self.presentation = presentation
        draw()
    }

    /// Takes the panel away without activating anything, because nothing was activated on the way in.
    func hide() {
        stopWatchingForLeaving()
        guard panel.isVisible else { return }
        panel.orderOut(nil)
    }

    var isVisible: Bool { panel.isVisible }

    // MARK: - Drawing

    private func draw() {
        hostingView.rootView = QuickPanelView(
            presentation: presentation,
            onKey: { [weak self] key in self?.relay(key) },
            onIntent: { [weak self] intent in self?.onIntent?(intent) },
            openCount: openCount)
    }

    /// `esc` closes here as well as being reported, so the panel is gone within the frame.
    private func relay(_ key: PanelKey) {
        if key == .escape { hide() }
        onKey?(key, caretOwner)
    }

    /// Deliberately empty: losing key is not the user leaving, and a notification banner takes key too.
    func windowDidResignKey(_ notification: Notification) {}

    /// Closes the panel on a click outside it or another application activating; neither needs a permission.
    private func watchForLeaving() {
        stopWatchingForLeaving()
        clicks = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            guard let self, panel.isVisible else { return }
            // In screen coordinates, which is what both of these already are.
            guard !panel.frame.contains(NSEvent.mouseLocation) else { return }
            relay(.escape)
        }
        switching = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let activated =
                note.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication
            // Uttrflow activating is the main window opening from this panel, not the user leaving.
            guard activated?.processIdentifier != ProcessInfo.processInfo.processIdentifier
            else { return }
            MainActor.assumeIsolated {
                guard let self, self.panel.isVisible else { return }
                self.relay(.escape)
            }
        }
    }

    private func stopWatchingForLeaving() {
        if let clicks { NSEvent.removeMonitor(clicks) }
        clicks = nil
        if let switching {
            NSWorkspace.shared.notificationCenter.removeObserver(switching)
        }
        switching = nil
    }

    // MARK: - Geometry

    /// The screen the pointer is on; `NSScreen.main` belongs to another application's key window here.
    private static func activeScreen() -> NSScreen? {
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens.first
    }

    /// Where the panel goes: where the user left it, or the top-right corner, via `PanelPlacement`.
    private func placedFrame(on screen: NSScreen?) -> CGRect {
        // The design's size on every open; a resize lasts only while the panel is on screen.
        let size = CGSize(width: QuickPanelMetrics.width, height: QuickPanelMetrics.height)
        // With no screen at all, a rectangle at the origin beats a crash.
        guard let visible = screen?.visibleFrame else { return CGRect(origin: .zero, size: size) }
        let origin = PanelPlacement.origin(
            remembered: rememberedOrigin, size: size, in: visible)
        return CGRect(
            x: origin.x.rounded(), y: origin.y.rounded(), width: size.width, height: size.height)
    }

    /// Remembers where the user puts the panel; guarded by `placedOrigin` because `show` moves it too.
    func windowDidMove(_ notification: Notification) {
        guard panel.isVisible, panel.frame.origin != placedOrigin else { return }

        // Clamped to the screen while dragging: a borderless panel goes clean under the menu bar otherwise.
        let visible = Self.activeScreen()?.visibleFrame
        let clamped =
            visible.map {
                PanelPlacement.clamped(panel.frame.origin, size: panel.frame.size, in: $0)
            } ?? panel.frame.origin
        if clamped != panel.frame.origin {
            // Ours, not theirs — so the move this causes is not read back as a drag.
            placedOrigin = clamped
            panel.setFrameOrigin(clamped)
        }
        UserDefaults.standard.set(Double(clamped.x), forKey: Self.originXKey)
        UserDefaults.standard.set(Double(clamped.y), forKey: Self.originYKey)
    }

    /// Applied whole, because every line follows from the one rule: never activate.
    private func configurePanel() {
        panel.delegate = self
        panel.isFloatingPanel = true
        // False, where the dock leaves it true: the search field must be typeable at once.
        panel.becomesKeyOnlyIfNeeded = false
        // Never true: the application is never active while this is open.
        panel.hidesOnDeactivate = false
        panel.worksWhenModal = true
        // Above the frontmost application's windows, on every Space, and beside a full-screen app.
        panel.level = .statusBar
        panel.collectionBehavior = [
            .canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle,
        ]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        // Rows, chips and buttons take their own drags first; this picks up the rest of the surface.
        panel.isMovableByWindowBackground = true
        // `.resizable` stays out of the style mask: the hosting view is the border's one owner.
        panel.isReleasedWhenClosed = false
        panel.acceptsMouseMovedEvents = true
        // Three keystrokes cannot feel instant from behind a fade.
        panel.animationBehavior = .none
        panel.contentView = hostingView
    }
}

extension PanelPresentation {
    /// An empty panel for the moment before the first snapshot; never seen on screen.
    static let placeholder = PanelPresentation(
        rows: [], filters: [], categories: [], query: "", searchPlaceholder: "",
        emptyState: nil, hint: "")
}
