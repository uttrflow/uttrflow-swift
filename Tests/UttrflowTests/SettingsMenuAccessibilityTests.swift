// Tests that a Settings pop-up is one VoiceOver stop that says what it is for and which option is chosen.

import AppKit
import ApplicationServices
import SwiftUI
import Testing

@testable import Uttrflow

@MainActor
@Suite(
    "A Settings pop-up's accessibility",
    .enabled(if: AXIsProcessTrusted(), "SwiftUI builds its tree only for a trusted client"))
struct SettingsMenuAccessibilityTests {
    /// Every accessibility element under `root`, depth first, read as an assistive app reads them.
    private func elements(under root: AnyObject) -> [AnyObject] {
        let children = (root.accessibilityChildren?() ?? []).map { $0 as AnyObject }
        return [root] + children.flatMap { elements(under: $0) }
    }

    /// The menu buttons the pop-up exposes, laid out in an offscreen window.
    private func menuButtons() async -> [AnyObject] {
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.finishLaunching()
        let window = NSWindow(
            contentRect: NSRect(x: -4_000, y: -4_000, width: 400, height: 80),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let menu = SettingsMenu(
            label: "Keep dictations for",
            options: [(id: "7", title: "7 days"), (id: "30", title: "30 days")],
            selection: .constant("30"))
        let host = NSHostingView(rootView: menu.padding(12))
        window.contentView = host
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        await askAsAnAssistiveApp()
        return elements(under: host).filter { $0.accessibilityRole?() == .menuButton }
    }

    @Test("the pop-up is one menu button, not one for the text and one for the chevron")
    func oneStop() async {
        #expect(await menuButtons().count == 1)
    }

    @Test("it is named by the row and its value is the chosen option")
    func namedWithItsValue() async throws {
        let button = try #require(await menuButtons().first)
        #expect((button.accessibilityLabel?() ?? nil) == "Keep dictations for")
        #expect(((button as? NSObject)?.value(forKey: "accessibilityValue") as? String) == "30 days")
    }
}
