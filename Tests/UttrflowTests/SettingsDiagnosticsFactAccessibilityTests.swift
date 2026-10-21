// Tests that a Diagnostics row with a button gives VoiceOver the status and the button as two named elements.

import AppKit
import ApplicationServices
import SwiftUI
import Testing
import UttrflowCore
import UttrflowUX

@testable import Uttrflow

@MainActor
@Suite(
    "Diagnostics rows in VoiceOver",
    .enabled(if: AXIsProcessTrusted(), "SwiftUI builds its tree only for a trusted client"),
    .serialized)
struct SettingsDiagnosticsFactAccessibilityTests {
    /// Every accessibility element under `root`, depth first, read as an assistive app reads them.
    private func elements(under root: AnyObject) -> [AnyObject] {
        let children = (root.accessibilityChildren?() ?? []).map { $0 as AnyObject }
        return [root] + children.flatMap { elements(under: $0) }
    }

    @Test("the button on a row is read by its own title and the status is read apart from it")
    func buttonKeepsItsTitle() async {
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.finishLaunching()
        let row = DiagnosticsRow(
            title: "Microphone", detail: "Not allowed", state: .attention,
            action: MainAction(
                title: "Open System Settings", intent: .recover(.openSystemSettings(.microphone))))
        let window = NSWindow(
            contentRect: NSRect(x: -4_000, y: -4_000, width: 720, height: 120),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = NSHostingView(
            rootView: SettingsDiagnosticsFact(row: row, icon: nil, isSystemValue: false).frame(width: 720))
        window.contentView = host
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        await askAsAnAssistiveApp()

        let all = elements(under: host)
        let buttons = all.filter { $0.accessibilityRole?() == .button }
        #expect(buttons.compactMap { $0.accessibilityLabel?() ?? nil } == ["Open System Settings"])
        #expect(all.contains { $0.accessibilityRole?() == .staticText }, "the status is not exposed")
    }
}
