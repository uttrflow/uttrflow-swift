import AppIntents
import AppKit
import SwiftUI
import Testing
import UttrflowClipboard
import UttrflowCore
import UttrflowInput

@testable import Uttrflow

@MainActor
@Suite("Small app-target wiring")
struct SmallWiringCoverageTests {
    @Test("Shortcuts offers start, stop, cancel and toggle, each with a phrase and a title")
    func appShortcutsOfferEveryDictationCommand() {
        let shortcuts = UttrflowAppShortcuts.appShortcuts
        #expect(shortcuts.count == 4)
    }

    @Test("a colour swatch lays out as a fixed square whatever the colour")
    func colourSwatchHasAFixedSize() {
        let host = NSHostingView(
            rootView: QuickPanelColourSwatch(colour: ClipColour(red: 0.2, green: 0.4, blue: 0.6, alpha: 1)))
        host.layoutSubtreeIfNeeded()
        #expect(host.fittingSize == NSSize(width: 22, height: 22))
    }

    @Test("a recorded edit command accepts the edits it knows and refuses other speech")
    func recordedEditCommandAcceptsOnlyEdits() async {
        let command = RecordedEditCommand(ledger: InsertionLedger())
        #expect(command.accepts("delete that"))
        #expect(command.accepts("undo that"))
        #expect(command.accepts("replace cat with dog"))
        #expect(!command.accepts("good morning everyone"))
        await #expect(throws: TextInsertionError.self) {
            _ = try await command.run("good morning everyone", on: AppContext.unknown)
        }
    }
}
