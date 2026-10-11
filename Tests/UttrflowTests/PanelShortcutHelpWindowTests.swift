import AppKit
import Testing
import UttrflowUX

@testable import Uttrflow

@MainActor
@Suite("Quick panel shortcut guide window", .serialized)
struct PanelShortcutHelpWindowTests {
    private func parent() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 800, height: 700), styleMask: [.titled],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        return window
    }

    @Test("a key other than the guide's is passed on, and opens no window")
    func otherKeysAreRelayed() {
        let window = parent()
        defer { window.close() }
        var relayed: [PanelKey] = []
        PanelShortcutHelpWindow.route(
            .down, relativeTo: window, relay: { key, _ in relayed.append(key) }, caretOwner: nil)
        #expect(relayed == [.down])
        #expect(window.childWindows?.isEmpty ?? true)
    }

    @Test("the guide key opens one centred panel over the parent and relays nothing")
    func guideKeyOpensTheGuide() throws {
        let window = parent()
        defer {
            PanelShortcutHelpWindow.close()
            window.close()
        }
        var relayed = false
        PanelShortcutHelpWindow.route(
            .showShortcuts, relativeTo: window, relay: { _, _ in relayed = true }, caretOwner: nil)
        PanelShortcutHelpWindow.route(
            .showShortcuts, relativeTo: window, relay: nil, caretOwner: nil)
        #expect(!relayed)
        let guide = try #require(window.childWindows?.first)
        #expect(window.childWindows?.count == 1)
        #expect(guide.title == "Keyboard Shortcuts")
        #expect(guide.frame.midX == window.frame.midX)
        guide.contentView?.layoutSubtreeIfNeeded()
    }

    @Test("the guide moves to a new parent when asked from another window")
    func guideFollowsItsParent() throws {
        let first = parent()
        let second = parent()
        defer {
            PanelShortcutHelpWindow.close()
            first.close()
            second.close()
        }
        PanelShortcutHelpWindow.route(.showShortcuts, relativeTo: first, relay: nil, caretOwner: nil)
        PanelShortcutHelpWindow.route(.showShortcuts, relativeTo: second, relay: nil, caretOwner: nil)
        #expect(first.childWindows?.isEmpty ?? true)
        #expect(second.childWindows?.count == 1)
    }

    @Test("closing the guide hides it")
    func closingHidesTheGuide() throws {
        let window = parent()
        defer { window.close() }
        PanelShortcutHelpWindow.route(.showShortcuts, relativeTo: window, relay: nil, caretOwner: nil)
        let guide = try #require(window.childWindows?.first)
        PanelShortcutHelpWindow.close()
        #expect(!guide.isVisible)
    }
}
