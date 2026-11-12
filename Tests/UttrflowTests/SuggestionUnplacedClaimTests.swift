// Tests that an offer with nowhere on the caret's line to draw it claims no key (#2076).

import AppKit
import Testing
import UttrflowContext
import UttrflowPredict

@testable import Uttrflow

/// A text area in a notes app, with or without a caret the reader could place.
private func field(caret: CGRect?, role: String = "AXTextArea") -> FocusedFieldSnapshot {
    let value = "Meet at"
    return FocusedFieldSnapshot(
        bundleIdentifier: "com.example.notes", applicationName: "Notes", role: role, value: value,
        selection: NSRange(location: value.utf16.count, length: 0), caret: caret, pointSize: 13)
}

/// A caret the panel can draw beside.
private let caret = CGRect(x: 200, y: 400, width: 1, height: 16)

@MainActor
@Suite("An offer that cannot be placed at the caret")
struct SuggestionUnplacedClaimTests {
    @Test("a field with a caret and an inline place gives the caret to draw at")
    func placedOfferHasACaret() {
        #expect(SuggestionRequest.caret(for: .certain("Meet at noon"), in: field(caret: caret)) == caret)
    }

    @Test("a field that reports no caret has nowhere to draw, so the draw disarms")
    func nilCaretIsUnplaced() {
        #expect(SuggestionRequest.caret(for: .certain("Meet at noon"), in: field(caret: nil)) == nil)
    }

    @Test("silence is never drawn, whatever the field offers")
    func silenceIsUnplaced() {
        #expect(SuggestionRequest.caret(for: .silent, in: field(caret: caret)) == nil)
    }

    @Test("a caret off every screen is not drawn, so show answers false and the draw disarms")
    func offScreenCaretIsNotShown() {
        let panel = SuggestionPanelController()
        let offScreen = CGRect(x: -100_000, y: -100_000, width: 1, height: 16)
        let shown = panel.show(
            .certain("Meet at noon"), typed: "Meet at", placement: .inlineGhost, caret: offScreen)
        #expect(!shown)
        #expect(!panel.isShowing)
    }
}
