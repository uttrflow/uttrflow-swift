import AppKit
import ApplicationServices
import SwiftUI
import Testing
import UttrflowUX

@testable import Uttrflow

@MainActor
@Suite(
    "Page sort menu in VoiceOver",
    .enabled(if: AXIsProcessTrusted(), "SwiftUI builds its tree only for a trusted client"))
struct PageSortMenuAccessibilityTests {
    private func elements(under root: AnyObject) -> [AnyObject] {
        let children = (root.accessibilityChildren?() ?? []).map { $0 as AnyObject }
        return [root] + children.flatMap { elements(under: $0) }
    }

    @Test("names the pop-up with the order in force once")
    func popUpIsNamedOnce() async {
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.finishLaunching()
        let window = NSWindow(
            contentRect: NSRect(x: -4_000, y: -4_000, width: 300, height: 60),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }

        let sort = MainScope(
            title: "Sorted by Newest",
            options: [
                MainScopeOption(id: "newest", title: "Newest", isSelected: true),
                MainScopeOption(id: "oldest", title: "Oldest", isSelected: false),
            ])
        let host = NSHostingView(rootView: PageSortMenu(sort: sort, onIntent: { _ in }))
        window.contentView = host
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        await askAsAnAssistiveApp()

        let popUps = elements(under: host).filter { element in
            (element as? any NSAccessibilityProtocol)?.accessibilityRole() == .popUpButton
        }
        let labels = popUps.map { $0.accessibilityLabel?() as? String }
        #expect(labels == ["Sorted by Newest"])
    }
}
