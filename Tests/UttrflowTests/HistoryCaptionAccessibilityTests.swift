// Tests that History's caption link is named by its own words and not by the dot beside it.

import AppKit
import ApplicationServices
import SwiftUI
import Testing
import UttrflowUX

@testable import Uttrflow

@MainActor
@Suite(
    "History's caption accessibility",
    .enabled(if: AXIsProcessTrusted(), "SwiftUI builds its tree only for a trusted client"))
struct HistoryCaptionAccessibilityTests {
    /// Every accessibility element under `root`, depth first, read as an assistive app reads them.
    private func elements(under root: AnyObject) -> [AnyObject] {
        let children = (root.accessibilityChildren?() ?? []).map { $0 as AnyObject }
        return [root] + children.flatMap { elements(under: $0) }
    }

    /// The caption's elements, laid out in an offscreen window `width` points wide.
    private func captionElements(width: CGFloat) async -> (elements: [AnyObject], host: NSView) {
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.finishLaunching()
        let window = NSWindow(
            contentRect: NSRect(x: -4_000, y: -4_000, width: width, height: 60),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let link = MainAction(title: "change in Settings › Privacy", intent: .go(.settings(.privacy)))
        let caption = HistoryCaptionView(
            text: "Every dictation, kept on this Mac · kept until you delete it", link: link,
            onIntent: { _ in })
        let host = NSHostingView(rootView: caption.frame(width: width, alignment: .leading))
        window.contentView = host
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        await askAsAnAssistiveApp()
        let found = elements(under: host)
        window.close()
        return (found, host)
    }

    @Test("the link is named by its words, with no separator dot in its name")
    func linkName() async {
        let found = await captionElements(width: 720).elements
        let buttons = found.filter { $0.accessibilityRole?() == .button }
            .compactMap { $0.accessibilityLabel?() ?? nil }
        #expect(buttons == ["change in Settings › Privacy"])
    }

    @Test("the separator dot is not an element of its own")
    func dotIsHidden() async {
        let found = await captionElements(width: 720).elements
        let labels = found.compactMap { $0.accessibilityLabel?() ?? nil }
        #expect(!labels.contains { $0.trimmingCharacters(in: .whitespaces) == "·" })
    }
}
