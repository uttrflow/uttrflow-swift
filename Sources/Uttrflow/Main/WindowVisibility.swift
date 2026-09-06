// Tells a view whether its window can be seen, so animations pause off screen.

import AppKit
import SwiftUI

/// Tells a view whether its window can be seen, from `NSWindow.occlusionState`. See Docs/app-main-window.md.
extension View {
    /// Calls `onChange` with whether this view's window is on screen, now and whenever it changes.
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
    /// The last answer given, so repeated occlusion notices do not restart a running animation.
    private var lastReported: Bool?

    /// Subscribes here because a view has no window until it is placed in one.
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

    /// Stops the animation while this view is out of the hierarchy, as switching pages does.
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
        guard lastReported != isVisible else { return }
        lastReported = isVisible
        onChange?(isVisible)
    }

    deinit { NotificationCenter.default.removeObserver(self) }
}
