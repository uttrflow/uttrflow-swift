// Tests that the History caption's link is named by its own words and stays whole when the window is narrow.

import AppKit
import ApplicationServices
import SwiftUI
import Testing
import UttrflowUX

@testable import Uttrflow

@MainActor
@Suite(
    "The History caption's accessibility",
    .enabled(if: AXIsProcessTrusted(), "SwiftUI builds its tree only for a trusted client"),
    .serialized)
struct HistoryCaptionAccessibilityTests {
    private let link = MainAction(title: "Change in Settings › Privacy", intent: .go(.settings(.privacy)))
    private let text = "Every dictation on this Mac · kept for 30 days"

    /// Every accessibility element under `root`, depth first, read as an assistive app reads them.
    private func elements(under root: AnyObject) -> [AnyObject] {
        let children = (root.accessibilityChildren?() ?? []).map { $0 as AnyObject }
        return [root] + children.flatMap { elements(under: $0) }
    }

    /// The caption's elements, laid out `width` wide in an offscreen window.
    private func captionElements(width: CGFloat) async -> [AnyObject] {
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.finishLaunching()
        let window = NSWindow(
            contentRect: NSRect(x: -4_000, y: -4_000, width: width, height: 40),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = NSHostingView(rootView: HistoryCaption(text: text, link: link).frame(width: width))
        window.contentView = host
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        await askAsAnAssistiveApp()
        return elements(under: host)
    }

    /// The caption's one button, as an assistive app finds it.
    private func button(width: CGFloat) async throws -> AnyObject {
        let buttons = await captionElements(width: width).filter { $0.accessibilityRole?() == .button }
        #expect(buttons.count == 1)
        return try #require(buttons.first)
    }

    @Test("the link is named by its own title, with no separator dot in its name")
    func linkIsNamedByItsTitle() async throws {
        let name = try await button(width: 720).accessibilityLabel?() ?? nil
        #expect(name == "Change in Settings › Privacy")
    }

    @Test("the separator dot is not read as an element of its own")
    func separatorIsHidden() async {
        let labels = await captionElements(width: 720).compactMap { element -> String? in
            let label = element.accessibilityLabel?() ?? nil
            let read: Any?? = element.accessibilityValue?()
            let value = read.flatMap { $0 } as? String
            return label ?? value
        }
        #expect(!labels.contains { $0.trimmingCharacters(in: CharacterSet.whitespaces) == "·" })
        #expect(!labels.contains { $0.hasPrefix(" ·") })
    }

    @Test("in a narrow window the link keeps the width it has in a wide one")
    func linkStaysWholeWhenNarrow() async throws {
        let wide = try await button(width: 720).accessibilityFrame?() ?? .zero
        let narrow = try await button(width: 220).accessibilityFrame?() ?? .zero
        #expect(wide.width > 0)
        #expect(narrow.width == wide.width)
    }
}
