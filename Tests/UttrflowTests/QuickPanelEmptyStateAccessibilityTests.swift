// Tests that the quick panel's empty-state icon stays out of the VoiceOver tree.

import AppKit
import ApplicationServices
import SwiftUI
import Testing
import UttrflowUX

@testable import Uttrflow

@MainActor
@Suite(
    "A quick panel empty state's accessibility",
    .enabled(if: AXIsProcessTrusted(), "SwiftUI builds its tree only for a trusted client"),
    .serialized
)
struct QuickPanelEmptyStateAccessibilityTests {
    private func actionNames(of element: AnyObject) -> Set<String> {
        let actions: [NSAccessibilityCustomAction] = (element.accessibilityCustomActions?() ?? nil) ?? []
        return Set(actions.map(\.name))
    }

    private func elements(under root: AnyObject) -> [AnyObject] {
        let children = (root.accessibilityChildren?() ?? []).map { $0 as AnyObject }
        return [root] + children.flatMap { elements(under: $0) }
    }

    private func emptyStateElements() async -> [AnyObject] {
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.finishLaunching()
        let window = NSWindow(
            contentRect: NSRect(x: -4_000, y: -4_000, width: 420, height: 360),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }

        let emptyState = MainEmptyState(
            symbolName: "doc.on.clipboard", title: "Nothing copied yet",
            message: "Whatever you copy turns up here, ready to put back.")
        let action = PanelAction(
            title: "Search all clips", symbolName: "magnifyingglass", intent: .keepQuery("meeting"))
        let presentation = PanelPresentation(
            rows: [], filters: [], categories: [], query: "meeting",
            searchPlaceholder: "Search", emptyState: emptyState, hint: "", emptyAction: action)
        let host = NSHostingView(rootView: QuickPanelView(presentation: presentation, openCount: 1))
        window.contentView = host
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        await askAsAnAssistiveApp()
        return elements(under: host)
    }

    @Test("the symbol is absent while the empty message and action remain accessible")
    func hidesOnlyTheDecorativeSymbol() async {
        let found = await emptyStateElements()
        // Static text speaks its words as its value, a control as its label.
        let labels = found.compactMap { element in
            (element.accessibilityLabel?() ?? nil)
                ?? ((element as? NSObject)?.value(forKey: "accessibilityValue") as? String)
        }
        let buttons = found.filter { $0.accessibilityRole?() == .button }
            .compactMap { $0.accessibilityLabel?() ?? nil }

        #expect(labels.contains("Nothing copied yet"))
        #expect(labels.contains("Whatever you copy turns up here, ready to put back."))
        #expect(!labels.contains("doc.on.clipboard"))
        #expect(buttons.contains("Search all clips"))
    }

    @Test("a collection chip exposes rename and delete actions to VoiceOver")
    func collectionChipActions() async {
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.finishLaunching()
        let window = NSWindow(
            contentRect: NSRect(x: -4_000, y: -4_000, width: 420, height: 360),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let presentation = PanelPresentation(
            rows: [], filters: [],
            categories: [
                PanelCategoryChip(
                    title: "Work", category: "Work", shortcut: 2, position: 2, isActive: false)
            ],
            query: "", searchPlaceholder: "Search", emptyState: nil, hint: "")
        let host = NSHostingView(rootView: QuickPanelView(presentation: presentation, openCount: 1))
        window.contentView = host
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        await askAsAnAssistiveApp()

        let chip = elements(under: host).first { $0.accessibilityLabel?() as? String == "Work" }
        #expect(chip.map(actionNames) == ["Rename collection", "Delete collection"])
    }
}
