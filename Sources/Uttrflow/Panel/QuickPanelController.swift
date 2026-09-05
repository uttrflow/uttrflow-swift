import AppKit
import UttrflowClipboard
import UttrflowUX
import SwiftUI

/// A floating window that takes typing without its application ever coming forward.
///
/// The sibling of ``DockPanel``, and its opposite in one respect only: this panel exists
/// to be typed into, so `canBecomeKey` is true where the dock's is false. Everything
/// else about it obeys the rule both panels obey — never activate.
///
/// The three parts have to hold together or the product breaks silently:
///
/// - `.nonactivatingPanel` in the style mask is what makes keyboard input possible at
///   all without activation. It is the documented purpose of that mask, and it is the
///   only reason the rest of this is achievable.
/// - `canBecomeKey` is true so the panel can hold first responder and the search field
///   can hold the caret.
/// - `canBecomeMain` is **false**. Becoming main is what drags application activation
///   along behind it, and activation is the thing that must not happen.
///
/// Why it matters more than tidiness: the paste path refuses to insert while Uttrflow is
/// itself the frontmost application — `PasteboardTextInsertionEngine.canInsert()` is
/// `!focus.isSelfFrontmost()`, and `isSelfFrontmost()` compares
/// `NSWorkspace.shared.frontmostApplication` to this process. Activating in order to get
/// keys would not throw and would not warn. Return would simply do nothing, and the clip
/// would be left sitting on the clipboard.
///
/// Measured, with the panel open over TextEdit and answering ↓ ↑ Return: frontmost
/// stayed `com.apple.TextEdit` for the whole session. Note that `NSApp.isActive` reads
/// `true` in that state — it is AppKit's own bookkeeping, not the system's idea of
/// frontmost, and anything that needs to know whether pasting will work must ask
/// `NSWorkspace`, as `isSelfFrontmost()` already does.
final class QuickPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// The panel's content, with the two things AppKit will not give a hosted view for free.
final class QuickPanelHostingView<Content: View>: NSHostingView<Content> {
    /// The panel floats over another application's window, and that application stays
    /// frontmost the whole time. Without this, the click that pastes a clip is swallowed
    /// as the click that merely brings a window forward — which, here, is every click.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Told after every step of a drag, so the controller can keep its own bookkeeping
    /// in step and not read the resize back as the user having moved the panel.
    var onResize: ((CGRect) -> Void)?

    /// The frame and the pointer when the current drag began, and which border it grabbed.
    ///
    /// Held from the start rather than accumulated, because a resize that added each
    /// step's delta to the last frame would lose whatever the minimum clamped away and
    /// then trail the pointer by exactly that much for the rest of the gesture.
    private var drag: (edge: PanelEdge, frame: CGRect, pointer: CGPoint)?

    /// The border claims the click; everything inside it belongs to the list.
    ///
    /// Done here rather than with a view laid over the panel, because the content view
    /// *is* this view — an overlay would need a container between the window and the
    /// hosting view, and every event that is not a resize would then be forwarded by
    /// hand. Returning `nil` for the whole middle hands SwiftUI its clicks untouched.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        if PanelResize.edge(at: local, in: bounds.size, isFlipped: isFlipped) != nil {
            return self
        }
        return super.hitTest(point)
    }

    /// The pointer says what the border will do before it is pressed, which is the whole
    /// affordance: a borderless window has no visible handle, so the cursor is the only
    /// thing that tells the user the edge is draggable at all.
    override func resetCursorRects() {
        super.resetCursorRects()
        // The same eight bands the hit test uses, from the same function, in this view's
        // own coordinates — which are flipped, because SwiftUI's origin is the top-left.
        // Written out by hand here, they were in AppKit's, so the cursor over the bottom
        // border promised a resize that the click there did not perform.
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
    /// The pointer that says what this border will do.
    ///
    /// `frameResize(position:directions:)` rather than `resizeLeftRight` and friends: the
    /// old pair has no diagonal, so a corner would have had to borrow a cursor that means
    /// something else — a crosshair says "draw a selection", which is the one gesture this
    /// border does not perform.
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

/// Owns the quick panel.
///
/// A window and a renderer, and nothing else. It is handed a `PanelPresentation` to
/// draw and reports the keys and intents that come back; the snapshot those keys are
/// applied to belongs to the app, which is also the only thing that can act on an
/// `.insert(Clip)`. Keeping the state out of here is what lets the whole of "which clip
/// does Return mean" be answered in a test with no screen anywhere near it.
@MainActor
final class QuickPanelController: NSObject, NSWindowDelegate {
    /// A keystroke, or the click that means the same as one. Apply it to the snapshot.
    ///
    /// The application that owned the caret when the panel opened is carried alongside,
    /// because by the time an insert is acted on the frontmost application is whatever
    /// the user has done since, and asking then answers a different question.
    var onKey: ((PanelKey, NSRunningApplication?) -> Void)?

    /// A row action the panel cannot answer itself — copy, pin, unpin — which the store
    /// carries out and the panel merely relays.
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

    /// The origin `show(_:)` last put the window at.
    ///
    /// A flag around `setFrame` is not enough: AppKit delivers `windowDidMove` on a later
    /// pass of the run loop, by which time the flag has been cleared and the panel's own
    /// placement is indistinguishable from the user having dragged it there. It then gets
    /// written down as a deliberate choice — which is harmless when the placement was the
    /// default corner and wrong the moment it was a position clamped back onto a screen
    /// that had changed. Comparing origins does not care when the notification arrives.
    private var placedOrigin: CGPoint?

    /// Where the user last dragged the panel, in screen coordinates, or `nil` if they
    /// never have. Two keys rather than an archived rectangle: the size is the design's
    /// to decide and must not be restored from a build that measured it differently.
    private static let originXKey = "com.uttrflow.panel.origin.x"
    private static let originYKey = "com.uttrflow.panel.origin.y"

    private var rememberedOrigin: CGPoint? {
        let defaults = UserDefaults.standard
        // `object(forKey:)` rather than `double(forKey:)`, which answers 0 for a key that
        // was never written — and 0,0 is the bottom-left corner, a real place the panel
        // would then open in for every user who has never moved it.
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
        // A drag on the left or bottom border moves the origin as well as the size, and
        // `windowDidMove` would write that down as the user having repositioned the panel
        // — so the next open, at the default size, would sit wherever the resize happened
        // to leave the corner. Claiming the origin as ours is the same mechanism `show`
        // uses, and it means a resize is remembered as exactly nothing.
        hostingView.onResize = { [weak self] frame in self?.placedOrigin = frame.origin }
        draw()
    }

    // MARK: - Lifecycle

    /// Puts the panel on screen, focused and ready to type into.
    ///
    /// `orderFrontRegardless` and then `makeKey`, and deliberately neither
    /// `makeKeyAndOrderFront` nor any form of `NSApplication.activate`. A
    /// `.nonactivatingPanel` becomes key inside its own process while the process
    /// underneath keeps the system's idea of frontmost — which is exactly the split this
    /// panel needs: our search field takes the typing, their text view keeps the caret
    /// the clip is going back to.
    func show(_ presentation: PanelPresentation) {
        // Recorded before the panel is ordered in, so the app is told where the clip
        // belongs rather than having to ask afterwards.
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

    /// Takes the panel away.
    ///
    /// Nothing is activated on the way out, because nothing was activated on the way in.
    /// The application underneath never stopped being frontmost, so its caret is already
    /// where the paste needs it — and calling `activate()` on it here would introduce a
    /// real activation, with a real race, in place of one that never happened.
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

    /// `esc` closes here as well as being reported, so the panel is gone within the
    /// frame rather than a round trip later.
    private func relay(_ key: PanelKey) {
        if key == .escape { hide() }
        onKey?(key, caretOwner)
    }

    /// Deliberately empty, and this is the whole fix.
    ///
    /// Losing key is not the same as the user going somewhere, and treating it as such
    /// made a **notification banner close the panel** — along with anything else that
    /// takes focus for a moment: a Bluetooth prompt, a permission sheet, a screenshot.
    /// The panel would vanish mid-use, taking whatever was half-typed into it, and the
    /// next keystrokes would land in whatever was behind. That is not a hypothetical; it
    /// happened while testing, and the stray keys reached another window.
    ///
    /// Dismissal now asks the question it actually means — see ``watchForLeaving()``.
    func windowDidResignKey(_ notification: Notification) {}

    /// Closes the panel when the user genuinely goes elsewhere.
    ///
    /// Two signals, and between them they mean "somewhere else", which key-loss does not:
    ///
    /// - A mouse-down anywhere outside the panel's own frame. This is a click away, which
    ///   is what A7 asks for, and a notification appearing is not one.
    /// - Another application being activated — ⌘Tab, the Dock, a click on a different
    ///   app. The panel is over whatever the user was doing, and once they are doing
    ///   something else it is in the way.
    ///
    /// Global mouse monitors need no permission; only keyboard ones do. So this costs the
    /// user nothing and works before Accessibility has been granted.
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
            // Uttrflow activating is not the user leaving — it is the main window opening
            // from this very panel.
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

    /// The screen the user is looking at, which is the one the pointer is on.
    ///
    /// `NSScreen.main` is the screen with the key window, and at the moment this is
    /// asked the key window belongs to another application — so on a second display it
    /// would be right only by luck.
    private static func activeScreen() -> NSScreen? {
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens.first
    }

    /// Where the panel goes this time: where the user left it, or the top-right corner.
    ///
    /// The arithmetic — the corner, and pulling a remembered position back onto a screen
    /// that has since changed — is `PanelPlacement`, in a module a test can reach. What
    /// is left here is the two things only AppKit knows: which screen, and how much of
    /// it the menu bar and Dock have already taken.
    private func placedFrame(on screen: NSScreen?) -> CGRect {
        // The design's size, every time, however the user left it last. A resize lasts as
        // long as the panel is on screen and no longer — which is what makes it safe to
        // offer at all: the panel is opened dozens of times a day by muscle memory, and a
        // size dragged once in a moment of curiosity would otherwise be the size it opens
        // at for ever, with nothing on screen to say why or how to undo it.
        let size = CGSize(width: QuickPanelMetrics.width, height: QuickPanelMetrics.height)
        // With no screen at all, a rectangle at the origin beats a crash: there is
        // nowhere better to put it and nobody there to see it.
        guard let visible = screen?.visibleFrame else { return CGRect(origin: .zero, size: size) }
        let origin = PanelPlacement.origin(
            remembered: rememberedOrigin, size: size, in: visible)
        return CGRect(
            x: origin.x.rounded(), y: origin.y.rounded(), width: size.width, height: size.height)
    }

    /// A7 — the panel stays where the user puts it.
    ///
    /// Guarded by ``placedOrigin`` because `show(_:)` moves the window itself on every
    /// open, and AppKit reports that move here like any other.
    func windowDidMove(_ notification: Notification) {
        guard panel.isVisible, panel.frame.origin != placedOrigin else { return }

        // Held inside the screen while it is being dragged, so the panel sticks to the
        // edges rather than going past them. A borderless panel gets none of AppKit's
        // usual protection here: dragged upwards it goes clean under the menu bar, and
        // the search field and first rows are simply gone. Reopening would pull it back,
        // but only after the user has lost the thing they were dragging.
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

    /// Applied whole rather than assembled from whatever each behaviour seems to need,
    /// because every line of it follows from the one rule: never activate.
    private func configurePanel() {
        panel.delegate = self
        panel.isFloatingPanel = true
        // False, where the dock leaves it true. The dock takes key only if something in
        // it ever demands the keyboard, and nothing ever does. Here the search field has
        // to be typeable before the user has finished looking at the panel, so the panel
        // is made key outright on the way in.
        panel.becomesKeyOnlyIfNeeded = false
        // Never true: the application is never active while this is open, so a panel
        // that hid itself on deactivation would be a panel nobody ever saw.
        panel.hidesOnDeactivate = false
        panel.worksWhenModal = true
        // Above the frontmost application's windows, which is how the panel is seen at
        // all without anything being brought forward to show it. `.fullScreenAuxiliary`
        // and `.canJoinAllSpaces` are the same trick for an app that has taken the whole
        // screen, which for a clipboard panel matters far more than it does for the dock.
        panel.level = .statusBar
        panel.collectionBehavior = [
            .canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle,
        ]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        // The user asked to be able to put the panel anywhere. Rows, chips and buttons
        // take their own drags first, so this only picks up the parts of the surface
        // that are not a control: the padding around the search field, the strip beside
        // the chips, the footer.
        panel.isMovableByWindowBackground = true
        // `.resizable` is deliberately *not* in the style mask. This panel is borderless,
        // so there is no frame view for AppKit to hang resize regions on, and whatever it
        // did provide would be competing with the border tracking in
        // `QuickPanelHostingView` for the same six points — with `isMovableByWindowBackground`
        // above also in the running for that click. One owner for the border, which is
        // the view, which is also the only one of the three that knows the minimum size.
        panel.isReleasedWhenClosed = false
        panel.acceptsMouseMovedEvents = true
        // Three keystrokes cannot feel instant from behind a fade.
        panel.animationBehavior = .none
        panel.contentView = hostingView
    }
}

extension PanelPresentation {
    /// An empty panel, for the moment between the controller being built and the first
    /// snapshot arriving. Never seen: the panel is not on screen until ``show(_:)``.
    static let placeholder = PanelPresentation(
        rows: [], filters: [], categories: [], query: "", searchPlaceholder: "",
        emptyState: nil, hint: "")
}
