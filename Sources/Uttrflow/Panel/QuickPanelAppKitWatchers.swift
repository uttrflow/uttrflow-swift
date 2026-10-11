// AppKit shims the quick panel needs because SwiftUI cannot see right-clicks or pointer movement here.

import AppKit
import SwiftUI

/// Claims right-clicks and ctrl-clicks in `hitTest` and lets every other click through to the row.
struct RightClickWatch: NSViewRepresentable {
    let clicked: () -> Void

    func makeNSView(context: Context) -> Catcher {
        let view = Catcher()
        view.clicked = clicked
        return view
    }

    func updateNSView(_ view: Catcher, context: Context) {
        view.clicked = clicked
    }

    final class Catcher: NSView {
        var clicked: (() -> Void)?
        var currentEvent: () -> NSEvent? = { NSApp.currentEvent }

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard bounds.contains(convert(point, from: superview)),
                let event = currentEvent()
            else { return nil }
            switch event.type {
            case .rightMouseDown, .rightMouseUp, .rightMouseDragged:
                return self
            case .leftMouseDown, .leftMouseUp:
                // A ctrl-click arrives as a left click carrying ⌃ and must open the menu too.
                return event.modifierFlags.contains(.control) ? self : nil
            default:
                return nil
            }
        }

        override func rightMouseDown(with event: NSEvent) { clicked?() }

        /// Answers the ctrl-click claimed in `hitTest`; a claimed press that does nothing is a dead press.
        override func mouseDown(with event: NSEvent) {
            if event.modifierFlags.contains(.control) { clicked?() } else { super.mouseDown(with: event) }
        }
    }
}

/// Reports the pointer entering and leaving even while Uttrflow is not the active application.
struct PointerWatch: NSViewRepresentable {
    let changed: (Bool) -> Void

    func makeNSView(context: Context) -> Tracker {
        let view = Tracker()
        view.changed = changed
        return view
    }

    func updateNSView(_ view: Tracker, context: Context) {
        view.changed = changed
    }

    final class Tracker: NSView {
        var changed: ((Bool) -> Void)?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            for area in trackingAreas { removeTrackingArea(area) }
            addTrackingArea(
                NSTrackingArea(
                    rect: .zero,
                    options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                    owner: self))
        }

        override func mouseEntered(with event: NSEvent) { changed?(true) }
        override func mouseExited(with event: NSEvent) { changed?(false) }

        /// Nothing here answers a click; the row behind it does.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
