// Tests that the Dictionary sidebar row is read to VoiceOver with its change count in the right number.

import AppKit
import ApplicationServices
import SwiftUI
import Testing
import UttrflowUX

@testable import Uttrflow

@MainActor
@Suite(
    "Sidebar row in VoiceOver",
    .enabled(if: AXIsProcessTrusted(), "SwiftUI builds its tree only for a trusted client"),
    .serialized)
struct SidebarRowAccessibilityTests {
    /// Every accessibility element under `root`, depth first, read as an assistive app reads them.
    private func elements(under root: AnyObject) -> [AnyObject] {
        let children = (root.accessibilityChildren?() ?? []).map { $0 as AnyObject }
        return [root] + children.flatMap { elements(under: $0) }
    }

    /// The label of the one button a Dictionary row exposes, laid out in an offscreen window.
    private func label(badge: String?) async -> String? {
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.finishLaunching()
        let window = NSWindow(
            contentRect: NSRect(x: -4_000, y: -4_000, width: 300, height: 60),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let item = SidebarItem(
            destination: .page(.dictionary), title: "Dictionary", symbolName: "book", badge: badge,
            isSelected: false)
        let host = NSHostingView(
            rootView: SidebarRow(item: item, isSelected: false, isExpanded: true, onSelect: {}))
        window.contentView = host
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        await askAsAnAssistiveApp()
        let buttons = elements(under: host).filter { $0.accessibilityRole?() == .button }
        return buttons.first.flatMap { $0.accessibilityLabel?() ?? nil }
    }

    @Test("the rendered row says one change in the singular, many in the plural, none by its title")
    func rowLabels() async {
        #expect(await label(badge: "1") == "Dictionary, 1 change today")
        #expect(await label(badge: "7") == "Dictionary, 7 changes today")
        #expect(await label(badge: nil) == "Dictionary")
    }
}
