// Tests that a SwiftUI selection trait moves with the selected control.

import AppKit
import ApplicationServices
import SwiftUI
import Testing
import UttrflowUX

@testable import Uttrflow

@MainActor
@Suite(
    "Selection traits in VoiceOver",
    .enabled(if: AXIsProcessTrusted(), "SwiftUI builds its tree only for a trusted client"))
struct AccessibilitySelectionTraitTests {
    private struct SelectionHarness: View {
        let selectedTab: SettingsTab
        let selectedPage: MainTab
        let isAccountSelected: Bool

        var body: some View {
            VStack {
                SettingsTabStrip(tabs: SettingsPresenter.tabs(), selected: selectedTab, onSelect: { _ in })
                SidebarRow(
                    item: item(.page(.home), "Home"), isSelected: selectedPage == .home, isExpanded: true,
                    onSelect: {})
                SidebarRow(
                    item: item(.settings(.general), "Settings", section: .footer),
                    isSelected: selectedPage == .account, isExpanded: true, onSelect: {})
                SidebarAccountCard(
                    account: .signedOut(open: MainAction(title: "Sign In", intent: .signIn)), picture: nil,
                    version: .unknown, isSelected: isAccountSelected, isExpanded: true, onOpen: {})
            }
        }

        private func item(
            _ destination: SidebarDestination, _ title: String, section: SidebarSection = .main
        ) -> SidebarItem {
            SidebarItem(
                destination: destination, title: title, symbolName: "circle", isSelected: false,
                section: section)
        }
    }

    private func elements(under root: AnyObject) -> [AnyObject] {
        let children = (root.accessibilityChildren?() ?? []).map { $0 as AnyObject }
        return [root] + children.flatMap { elements(under: $0) }
    }

    @Test("the selected trait moves off the previous tab and onto the new tab")
    func traitMovesWithSelection() {
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.finishLaunching()
        let window = NSWindow(
            contentRect: NSRect(x: -4_000, y: -4_000, width: 300, height: 80),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }

        let host = NSHostingView(
            rootView: SelectionHarness(
                selectedTab: .privacy, selectedPage: .account, isAccountSelected: true))
        window.contentView = host
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        askAsAnAssistiveApp()

        func selectedLabels() -> Set<String> {
            Set(
                elements(under: host).compactMap { element in
                    guard element.accessibilityRole?() == .button,
                        element.isAccessibilitySelected?() == true
                    else { return nil }
                    return element.accessibilityLabel?() ?? nil
                })
        }

        #expect(selectedLabels() == ["Privacy", "Settings", "Sign In"])

        host.rootView = SelectionHarness(
            selectedTab: .general, selectedPage: .home, isAccountSelected: false)
        host.layoutSubtreeIfNeeded()
        askAsAnAssistiveApp()

        #expect(selectedLabels() == ["General", "Home"])
    }
}
