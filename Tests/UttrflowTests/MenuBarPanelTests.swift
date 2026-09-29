// Tests that the menu bar popover's panel takes the keyboard, closes on Escape, and empties when closed.

import AppKit
import Testing
import UttrflowUX

@testable import Uttrflow

@MainActor
@Suite("The menu bar popover's panel")
struct MenuBarPanelTests {
    private static func panel() -> MenuBarPanel {
        MenuBarPanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true
        )
    }

    @Test("can take the keyboard, so Tab, the arrows, Return and VoiceOver reach the popover")
    func becomesKey() {
        let panel = Self.panel()
        #expect(panel.canBecomeKey)
        #expect(!panel.canBecomeMain)
    }

    @Test("reports Escape, so the popover closes as a menu does")
    func escapeCancels() {
        let panel = Self.panel()
        var cancelled = 0
        panel.onCancel = { cancelled += 1 }
        panel.cancelOperation(nil)
        #expect(cancelled == 1)
    }

    @Test("draws nothing while closed, so a sliding bar cannot keep running behind the hidden panel")
    func emptyWhileClosed() {
        let loading = MenuBarPresenter.present(MenuBarState(speechModel: .loading))
        let bar = MenuBarController(initial: loading)
        defer { bar.removeFromMenuBar() }
        #expect(!bar.isPopoverContentHosted)
        bar.openMenu()
        #expect(bar.isPopoverShown)
        #expect(bar.isPopoverContentHosted)
        bar.closePopover()
        #expect(!bar.isPopoverShown)
        #expect(!bar.isPopoverContentHosted)
        bar.update(with: loading)
        #expect(!bar.isPopoverContentHosted)
        bar.openMenu()
        #expect(bar.isPopoverContentHosted)
        bar.closePopover()
    }

    @Test("A development build labels the menu-bar item Dev in blue")
    func developmentBuildHasBlueDevLabel() {
        let title = MenuBarController.title(isDevelopmentBuild: true, iconMissing: false)
        #expect(title.string == "Dev")
        #expect(title.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == .systemBlue)
    }
}
