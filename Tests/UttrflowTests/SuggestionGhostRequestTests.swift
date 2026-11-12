// The inline ghost the coordinator asks the panel for, built from the field read and the person's choices.

import AppKit
import Testing
import UttrflowContext
import UttrflowPredict

@testable import Uttrflow

@Suite struct SuggestionGhostRequestTests {
    private static let caret = CGRect(x: 200, y: 400, width: 1, height: 16)
    private static let bundle = "com.example.notes"

    /// A text area holding `value` with the caret at `caretAt`, or at its end.
    private static func field(
        _ value: String, caretAt: Int? = nil, caret: CGRect? = Self.caret,
        direction: WritingDirection = .leftToRight
    ) -> FocusedFieldSnapshot {
        FocusedFieldSnapshot(
            bundleIdentifier: bundle, applicationName: "Notes", role: "AXTextArea", value: value,
            selection: NSRange(location: caretAt ?? value.utf16.count, length: 0), caret: caret,
            writingDirection: direction, field: CGRect(x: 100, y: 380, width: 600, height: 40), pointSize: 13,
            fontFamily: "Menlo", isBold: true)
    }

    @Test("the ghost is drawn at the caret in the field's own face, keyed as chosen for this app")
    func carriesTheFieldAndTheKeys() throws {
        let preferences = SuggestionPreferences(
            isEnabled: true, chosenAcceptKeys: [Self.bundle: .rightArrow],
            chosenWordAcceptKeys: [Self.bundle: .optionRightArrow])
        let snapshot = Self.field("Meet at")

        let ghost = try #require(
            SuggestionRequest.ghost(
                .certain("Meet at noon"), typed: "Meet at", selection: .untouched, in: snapshot,
                preferences: preferences))

        #expect(ghost.suggestion == .certain("Meet at noon"))
        #expect(ghost.typed == "Meet at")
        #expect(ghost.placement == .inlineGhost)
        #expect(ghost.caret == Self.caret)
        #expect(ghost.field == snapshot.ghostField)
        #expect(ghost.fieldPointSize == 13)
        #expect(ghost.acceptKey == .rightArrow)
        #expect(ghost.wordAcceptKey == .optionRightArrow)
        #expect(ghost.fontFamily == "Menlo" && ghost.isBold && !ghost.isItalic)
        #expect(ghost.direction == .leftToRight)
    }

    @Test("closing punctuation already after the caret is not drawn again")
    func dropsTheClosersAlreadyThere() throws {
        let ghost = try #require(
            SuggestionRequest.ghost(
                .certain("print(total)"), typed: "print(", selection: .untouched,
                in: Self.field("print()", caretAt: 6), preferences: SuggestionPreferences(isEnabled: true)))

        #expect(ghost.suggestion == .certain("print(total"))
    }

    @Test("a right-to-left field draws right to left, and an unknown direction left to right")
    func followsTheWritingDirection() throws {
        let preferences = SuggestionPreferences(isEnabled: true)
        let rightToLeft = try #require(
            SuggestionRequest.ghost(
                .certain("Meet at noon"), typed: "Meet at", selection: .untouched,
                in: Self.field("Meet at", direction: .rightToLeft), preferences: preferences))
        let unknown = try #require(
            SuggestionRequest.ghost(
                .certain("Meet at noon"), typed: "Meet at", selection: .untouched,
                in: Self.field("Meet at", direction: .unknown), preferences: preferences))

        #expect(rightToLeft.direction == .rightToLeft)
        #expect(unknown.direction == .leftToRight)
    }

    @Test("no wordwise key is armed where the person chose none")
    func noWordKeyUnlessChosen() throws {
        let ghost = try #require(
            SuggestionRequest.ghost(
                .certain("Meet at noon"), typed: "Meet at", selection: .untouched, in: Self.field("Meet at"),
                preferences: SuggestionPreferences(isEnabled: true)))

        #expect(ghost.wordAcceptKey == nil)
    }

    @Test("silence, or a field with no caret, has no ghost")
    func nothingWithoutAPlace() {
        let preferences = SuggestionPreferences(isEnabled: true)

        #expect(
            SuggestionRequest.ghost(
                .silent, typed: "Meet at", selection: .untouched, in: Self.field("Meet at"),
                preferences: preferences) == nil)
        #expect(
            SuggestionRequest.ghost(
                .certain("Meet at noon"), typed: "Meet at", selection: .untouched,
                in: Self.field("Meet at", caret: nil), preferences: preferences) == nil)
    }

    @Test("the accept key is the one the person chose for the field's app")
    func acceptKeyFollowsTheChoice() {
        for chosen in AcceptKey.allCases {
            let preferences = SuggestionPreferences(isEnabled: true, chosenAcceptKeys: [Self.bundle: chosen])
            #expect(
                SuggestionRequest.acceptKey(in: Self.field("Meet at"), preferences: preferences) == chosen)
        }
    }
}
