// Tests that a page explanation belongs to the heading rather than every control on the card.

import AppKit
import ApplicationServices
import SwiftUI
import UttrflowSettings
import Testing

@testable import Uttrflow
@testable import UttrflowUX

@MainActor
@Suite(
    "Onboarding card accessibility",
    .enabled(if: AXIsProcessTrusted(), "SwiftUI builds its tree only for a trusted client"))
struct OnboardingCardAccessibilityTests {
    private func elements(under root: AnyObject) -> [AnyObject] {
        let children = (root.accessibilityChildren?() ?? []).map { $0 as AnyObject }
        return [root] + children.flatMap { elements(under: $0) }
    }

    @Test("page explanation is announced by the heading and not repeated as control help")
    func explanationStaysOnTheHeading() {
        let page = OnboardingPresenter.page(
            for: OnboardingState(step: .signIn, detail: .signIn(.signingIn(.google))),
            hotkey: Settings.default.hotkey)
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.finishLaunching()
        let window = NSWindow(
            contentRect: NSRect(x: -4_000, y: -4_000, width: OnboardingMetrics.cardWidth, height: 500),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }

        let host = NSHostingView(rootView: OnboardingCard(page: page, press: { _ in }))
        window.contentView = host
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        askAsAnAssistiveApp()

        let found = elements(under: host)
        // The heading role constant is macOS 26 only; its raw value is what older systems report too.
        let headings = found.filter { $0.accessibilityRole?() == NSAccessibility.Role(rawValue: "AXHeading") }
        let buttons = found.filter { $0.accessibilityRole?() == .button }
        let indicators = found.filter { $0.accessibilityLabel?() == "Step 1 of 6: Sign in" }
        #expect(headings.contains { ($0.accessibilityLabel?() ?? "").contains(page.explanation ?? "") })
        let buttonLabels = Set(buttons.compactMap { $0.accessibilityLabel?() })
        #expect(buttonLabels.isSuperset(of: ["Reopen", "Cancel"]))
        #expect(indicators.count == 1)
        #expect((buttons + indicators).allSatisfy { ($0.accessibilityHelp?() ?? nil) == nil })
    }
}
