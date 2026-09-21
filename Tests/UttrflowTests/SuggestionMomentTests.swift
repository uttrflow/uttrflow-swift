// Tests what one reading of the focused field becomes for capture, the quieting rules and the model.

import Foundation
import Testing
import UttrflowContext
import UttrflowPredict
import UttrflowPredictCapture

@testable import Uttrflow

/// A field in a mail composer, with a line above the caret's line and a caret at its end.
private func composer(
    subrole: String? = nil, value: String = "Dear team,\nThanks for", role: String = "AXTextArea"
) -> FocusedFieldSnapshot {
    FocusedFieldSnapshot(
        bundleIdentifier: "com.Example.Mail", applicationName: "Mail", role: role, subrole: subrole,
        identifier: "body", placeholder: "Message", accessibilityDescription: "Message body",
        document: "draft", value: value, selection: NSRange(location: value.utf16.count, length: 0),
        caret: CGRect(x: 10, y: 10, width: 1, height: 14), pointSize: 13, isComposing: true,
        windowTitle: "Re: plans")
}

@Suite("What a reading of the focused field becomes")
struct SuggestionMomentTests {
    @Test("A password field reads as secure, so capture refuses it")
    func aSecureFieldReadsSecure() {
        let reading = SuggestionMoment.reading(of: composer(subrole: "AXSecureTextField"))
        #expect(reading.isSecure)
        #expect(reading.subrole == "AXSecureTextField")
        #expect(!SuggestionMoment.reading(of: composer()).isSecure)
    }

    @Test("The bundle identifier and everything else the field publishes pass through unchanged")
    func theReadingKeepsWhatTheFieldSaid() {
        let reading = SuggestionMoment.reading(of: composer())
        #expect(
            reading
                == FieldReading(
                    bundleIdentifier: "com.Example.Mail", role: "AXTextArea", identifier: "body",
                    placeholder: "Message", accessibilityDescription: "Message body", document: "draft",
                    windowTitle: "Re: plans", applicationName: "Mail"))
    }

    @Test("The context carries the caret's line, the pause and every fact the rules quiet on")
    func theContextCarriesTheMoment() {
        let context = SuggestionMoment.context(of: composer(), millisecondsSinceKeystroke: 250)
        #expect(context.typed == "Thanks for")
        #expect(context.caretAtLineEnd)
        #expect(!context.hasSelection)
        #expect(context.isComposing)
        #expect(!context.isSecure)
        #expect(context.isProse)
        #expect(context.millisecondsSinceKeystroke == 250)
        #expect(context.canDraw)
        let nowhere = FocusedFieldSnapshot(bundleIdentifier: "a.b", applicationName: "B", role: "AXTextField")
        #expect(!SuggestionMoment.context(of: nowhere, millisecondsSinceKeystroke: 0).canDraw)
    }

    @Test("The situation holds the preceding text, the screen around the field and the recent lines")
    func theSituationHoldsWhatTheSnapshotHolds() {
        let around = Surroundings(windowTitle: "Re: plans", text: "See you at the north gate")
        let situation = SuggestionMoment.situation(
            of: composer(), surroundings: around, recentLines: ["Thanks, see you then"])
        #expect(situation.application == "Mail")
        #expect(situation.field == "Message body")
        #expect(situation.document == "draft")
        #expect(situation.preceding == "Dear team,")
        #expect(situation.windowTitle == "Re: plans")
        #expect(situation.surroundings == "See you at the north gate")
        #expect(situation.recentLines == ["Thanks, see you then"])
        #expect(situation.isMultiline)
    }

    @Test("With nothing around it, a single-line field is named by its placeholder or its role")
    func aBareFieldIsNamedByWhatItHas() {
        let bare = FocusedFieldSnapshot(
            bundleIdentifier: "a.b", applicationName: "B", role: "AXTextField", placeholder: "Search",
            value: "ab")
        let situation = SuggestionMoment.situation(of: bare, surroundings: nil, recentLines: [])
        #expect(situation.field == "Search")
        #expect(situation.windowTitle == nil)
        #expect(situation.surroundings == nil)
        #expect(!situation.isMultiline)
        let roleOnly = FocusedFieldSnapshot(
            bundleIdentifier: "a.b", applicationName: "B", role: "AXTextField")
        #expect(
            SuggestionMoment.situation(of: roleOnly, surroundings: nil, recentLines: []).field
                == "AXTextField")
    }

    @Test("A remembered line the line being written already begins with is not shown back to the model")
    func theLineBeingWrittenIsNotRecent() {
        #expect(
            SuggestionMoment.recentLines(["Thanks", "See you", "Thanks for"], typing: "Thanks for coming")
                == ["See you"])
    }
}
