// Tests that a History row's buttons and actions reach VoiceOver while no pointer is over the row.

import AppKit
import ApplicationServices
import SwiftUI
import Testing
import UttrflowUX

@testable import Uttrflow

@MainActor
@Suite(
    "A History row's accessibility",
    .enabled(if: AXIsProcessTrusted(), "SwiftUI builds its tree only for a trusted client"))
struct HistoryRailRowAccessibilityTests {
    /// A dictation with the page's three buttons, and Delete offered only in the menu.
    private let row = HistoryRow(
        id: UUID(), application: nil, when: "2 minutes ago", text: "Meet at the north gate at noon",
        time: "10:41", length: "0:04 · 7 words",
        actions: [
            MainAction(title: "Copy", symbolName: "doc.on.doc", intent: .copy("Meet")),
            MainAction(
                title: "Copy to Paste Elsewhere", symbolName: "arrow.turn.down.left", intent: .copy("Meet")),
            MainAction(title: "Flag", symbolName: "flag", intent: .flagDictation(UUID())),
        ],
        more: [MainAction(title: "Delete", symbolName: "trash", intent: .copy("Meet"), isDestructive: true)])

    /// Every accessibility element under `root`, depth first, read as an assistive app reads them.
    private func elements(under root: AnyObject) -> [AnyObject] {
        let children = (root.accessibilityChildren?() ?? []).map { $0 as AnyObject }
        return [root] + children.flatMap { elements(under: $0) }
    }

    /// The names of the actions rotor entries on `element`.
    private func actionNames(of element: AnyObject) -> Set<String> {
        let actions: [NSAccessibilityCustomAction] = (element.accessibilityCustomActions?() ?? nil) ?? []
        return Set(actions.map(\.name))
    }

    /// The row's elements, laid out in an offscreen window that no pointer is over.
    private func rowElements() async -> [AnyObject] {
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.finishLaunching()
        let window = NSWindow(
            contentRect: NSRect(x: -4_000, y: -4_000, width: 720, height: 120),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = NSHostingView(
            rootView: HistoryRailRow(row: row, index: 0, count: 1, onIntent: { _ in }).frame(width: 720))
        window.contentView = host
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        await askAsAnAssistiveApp()
        return elements(under: host)
    }

    @Test("the row's buttons stay in the tree while no pointer is over the row")
    func buttonsStayInTheTree() async {
        let buttons = await rowElements()
            .filter { $0.accessibilityRole?() == .button }
            .compactMap { $0.accessibilityLabel?() ?? nil }
        #expect(Set(buttons).isSuperset(of: ["Copy", "Copy to Paste Elsewhere", "Flag"]))
    }

    @Test("the card that holds the row offers every action, Delete included, and nothing else carries them")
    func theCardOffersEveryAction() async {
        let found = await rowElements()
        let carriers = found.filter { !actionNames(of: $0).isEmpty }
        #expect(carriers.count == 1)
        #expect(carriers.first?.accessibilityRole?() == .group)
        #expect(carriers.first.map(actionNames) == ["Copy", "Copy to Paste Elsewhere", "Flag", "Delete"])
    }
}
