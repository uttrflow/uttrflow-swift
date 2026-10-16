// Tests that a page's sort pop-up reaches VoiceOver with its name once and the order in force as its value.

import AppKit
import ApplicationServices
import SwiftUI
import Testing
import UttrflowUX

@testable import Uttrflow

@MainActor
@Suite(
    "A page's sort pop-up accessibility",
    .enabled(if: AXIsProcessTrusted(), "SwiftUI builds its tree only for a trusted client"))
struct PageSortMenuAccessibilityTests {
    /// Every accessibility element under `root`, depth first, read as an assistive app reads them.
    private func elements(under root: AnyObject) -> [AnyObject] {
        let children = (root.accessibilityChildren?() ?? []).map { $0 as AnyObject }
        return [root] + children.flatMap { elements(under: $0) }
    }

    /// The pop-up buttons the menu exposes, laid out in an offscreen window.
    private func popUps() async -> [AnyObject] {
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.finishLaunching()
        let window = NSWindow(
            contentRect: NSRect(x: -4_000, y: -4_000, width: 400, height: 60),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let sort = DictionarySort.standard.menu
        let host = NSHostingView(rootView: PageSortMenu(sort: sort, onIntent: { _ in }).padding(8))
        window.contentView = host
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        await askAsAnAssistiveApp()
        return elements(under: host).filter { $0.accessibilityRole?() == .popUpButton }
    }

    @Test("the pop-up is named once, by the order in force")
    func namedOnce() async {
        let names = await popUps().compactMap { $0.accessibilityLabel?() ?? nil }
        #expect(names == ["Sorted by Newest"])
    }
}
