import AppKit
import SwiftUI

/// Tells a view whether the window it is in can actually be seen.
///
/// Written for one specific bug, and the shape of it is the bug's. `TimelineView(.animation)`
/// asks to be redrawn every display refresh and keeps asking for as long as the view
/// exists — it does not stop when the window is behind another one, minimised, hidden,
/// or on a Space nobody is looking at. Uttrflow opens its window at login and is meant to
/// be left open, so an animation on that window is an animation that runs all day: the
/// home page's demonstration was measured holding a whole core busy from the moment the
/// app launched, for as long as it stayed running.
///
/// macOS already knows the answer and publishes it as `NSWindow.occlusionState`. Nothing
/// in SwiftUI surfaces it, so this reaches back through an `NSView` to find the window
/// and watches the two notifications that can change it:
///
/// - `NSWindow.didChangeOcclusionStateNotification` — covered, uncovered, minimised, or
///   moved to another Space.
/// - `NSApplication.didHideNotification` / `didUnhideNotification` — ⌘H, which does
///   *not* always move the window's own occlusion state, and which is exactly how
///   somebody puts this app away without closing it.
///
/// Deliberately errs towards visible: a window it cannot find is reported as on screen.
/// Being wrong that way costs the frames it was going to draw anyway, and being wrong
/// the other way freezes an animation somebody is looking at.
extension View {
    /// Calls `onChange` with whether this view's window is on screen, now and whenever it
    /// changes.
    func onWindowVisibilityChange(_ onChange: @escaping (Bool) -> Void) -> some View {
        background(WindowVisibilityReporter(onChange: onChange).allowsHitTesting(false))
    }
}

/// A zero-sized `NSView` whose only job is to have a `window`.
private struct WindowVisibilityReporter: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = VisibilityReportingView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        (view as? VisibilityReportingView)?.onChange = onChange
    }
}

private final class VisibilityReportingView: NSView {
    var onChange: ((Bool) -> Void)?
    /// The last answer given, so an occlusion change that does not change the answer —
    /// and macOS sends several — does not restart an animation that is already running.
    private var reported: Bool?

    /// Subscribed here rather than at construction because a view has no window until it
    /// is placed in one, and the first answer has to be given once there is something to
    /// answer about.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        let centre = NotificationCenter.default
        centre.removeObserver(self)
        guard let window else {
            report(true)
            return
        }
        centre.addObserver(
            self, selector: #selector(recheck),
            name: NSWindow.didChangeOcclusionStateNotification, object: window)
        for name in [NSApplication.didHideNotification, NSApplication.didUnhideNotification] {
            centre.addObserver(self, selector: #selector(recheck), name: name, object: nil)
        }
        recheck()
    }

    /// Stops the animation while this view is out of the hierarchy at all — which is what
    /// switching to another page in the sidebar does.
    override func viewDidHide() {
        super.viewDidHide()
        report(false)
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        recheck()
    }

    @objc private func recheck() {
        guard let window else { return report(true) }
        report(window.occlusionState.contains(.visible) && !NSApp.isHidden)
    }

    private func report(_ isVisible: Bool) {
        guard reported != isVisible else { return }
        reported = isVisible
        onChange?(isVisible)
    }

    deinit { NotificationCenter.default.removeObserver(self) }
}
