import AppKit
import ApplicationServices
import SwiftUI
import Testing
import UttrflowCore
import UttrflowHistory
import UttrflowSettings
import UttrflowUX

@testable import Uttrflow

@MainActor
@Suite(
    "Settings version in VoiceOver",
    .enabled(if: AXIsProcessTrusted(), "SwiftUI builds its tree only for a trusted client"))
struct SettingsVersionAccessibilityTests {
    private struct Store: SettingsStore {
        func load() -> UttrflowSettings.Settings { .default }
        func save(_: UttrflowSettings.Settings) {}
    }

    private struct Personalisation: SettingsPersonalisationStore {
        func personalisation(keeping _: Retention) async -> SettingsPersonalisation {
            SettingsPersonalisation(learnedWords: 0, addedWords: 0, transcripts: 0)
        }

        func carryOut(_: SettingsReset) async throws(SettingsResetFailure) {}
    }

    private func elements(under root: AnyObject) -> [AnyObject] {
        let children = (root.accessibilityChildren?() ?? []).map { $0 as AnyObject }
        return [root] + children.flatMap { elements(under: $0) }
    }

    @Test("keeps the version number available as the Version row value")
    func versionIsTheAccessibilityValue() async {
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.finishLaunching()
        let window = NSWindow(
            contentRect: NSRect(x: -4_000, y: -4_000, width: 400, height: 100),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }

        let model = SettingsViewModel(
            store: Store(), personalisation: Personalisation(), capabilities: .everything)
        let version = "26.0930.0 (42)"
        let row = SettingsRow(id: "version", label: "Version", control: .text(version))
        let host = NSHostingView(rootView: SettingsRowView(row: row, model: model, paneUnavailability: nil))
        window.contentView = host
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        await askAsAnAssistiveApp()

        let versionElement = elements(under: host).first { element in
            // SwiftUI's elements are neither views nor `NSAccessibilityElement`s, but they adopt the protocol.
            let value = (element as? any NSAccessibilityProtocol)?.accessibilityValue()
            return element.accessibilityLabel?() as? String == "Version" && value as? String == version
        }
        #expect(versionElement != nil)
    }
}
