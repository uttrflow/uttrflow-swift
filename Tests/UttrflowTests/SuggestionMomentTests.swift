// Tests what one reading of the focused field becomes for capture, the quieting rules and the model.

import Foundation
import Testing
import UttrflowContext
import UttrflowPredict
import UttrflowPredictCapture

@testable import Uttrflow

/// A field in a mail composer, with a line above the caret's line and a caret at its end.
private func composer(
    subrole: String? = nil, value: String = "Dear team,\nThanks for", role: String = "AXTextArea",
    title: String? = nil,
    isEnabled: Bool? = nil, isComposing: Bool = true
) -> FocusedFieldSnapshot {
    FocusedFieldSnapshot(
        bundleIdentifier: "com.Example.Mail", applicationName: "Mail", role: role, subrole: subrole,
        identifier: "body", placeholder: "Message", accessibilityDescription: "Message body",
        title: title, document: "draft", value: value,
        selection: NSRange(location: value.utf16.count, length: 0),
        caret: CGRect(x: 10, y: 10, width: 1, height: 14), pointSize: 13, isEnabled: isEnabled,
        isComposing: isComposing,
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

    @Test("A field the read found secure only by its masked value stays secure")
    func aMaskedOnlyFieldReadsSecure() {
        let snapshot = FocusedFieldSnapshot(
            bundleIdentifier: "com.example.app", applicationName: "App", role: "AXTextField", isSecure: true)
        #expect(SuggestionMoment.reading(of: snapshot).isSecure)
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
        #expect(!context.showsOwnList)
        let listing = FocusedFieldSnapshot(
            bundleIdentifier: "a.b", applicationName: "B", role: "AXTextField", showsOwnList: true)
        #expect(SuggestionMoment.context(of: listing, millisecondsSinceKeystroke: 0).showsOwnList)
    }

    @Test("A command with spaced text after the caret is quieted as an interior caret.")
    func aSpacedCommandTailDoesNotOfferACompletion() {
        let value = "ls -la    # list"
        let snapshot = FocusedFieldSnapshot(
            bundleIdentifier: "com.apple.Terminal", applicationName: "Terminal", role: "AXTextArea",
            value: value, selection: NSRange(location: "ls -la".utf16.count, length: 0),
            caret: CGRect(x: 10, y: 10, width: 1, height: 14))
        let context = SuggestionMoment.context(of: snapshot, millisecondsSinceKeystroke: 250)
        #expect(Quieting.reason(context) == .caretInsideText)
    }

    @Test("A disabled field refuses a suggestion before generation")
    func disabledFieldCannotDraw() {
        let context = SuggestionMoment.context(
            of: composer(isEnabled: false, isComposing: false), millisecondsSinceKeystroke: 500)
        #expect(!context.canDraw)
        #expect(Quieting.reason(context) == .nowhereToDraw)
    }

    @Test("The situation holds the preceding text, the screen around the field and the recent lines")
    func theSituationHoldsWhatTheSnapshotHolds() {
        let around = Surroundings(windowTitle: "Re: plans", text: "See you at the north gate")
        let situation = SuggestionMoment.situation(
            of: composer(), surroundings: around, recentLines: ["Thanks, see you then"])
        #expect(situation.application == "Mail")
        #expect(situation.field == "Message")
        #expect(situation.document == "draft")
        #expect(situation.preceding == "Dear team,")
        #expect(situation.windowTitle == "Re: plans")
        #expect(situation.surroundings == "See you at the north gate")
        #expect(situation.recentLines == ["Thanks, see you then"])
        #expect(situation.isMultiline)
    }

    @Test("A field title takes priority over placeholder and description for the prompt locator")
    func titleNamesThePromptField() {
        let situation = SuggestionMoment.situation(
            of: composer(title: "Search"), surroundings: nil, recentLines: [])
        #expect(situation.field == "Search")
    }

    @Test("Terminal scrollback does not make a shell command multiline")
    func terminalScrollbackIsNotMultiline() {
        let terminal = FocusedFieldSnapshot(
            bundleIdentifier: "com.apple.Terminal", applicationName: "Terminal", role: "AXTextArea",
            value: "previous command\ngit che")
        let terminalSituation = SuggestionMoment.situation(of: terminal, surroundings: nil, recentLines: [])
        let composerSituation = SuggestionMoment.situation(
            of: composer(), surroundings: nil, recentLines: [])

        #expect(!terminalSituation.isMultiline)
        #expect(composerSituation.isMultiline)
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

    @Test("The place an answer is remembered at is exactly the preceding text the model is shown")
    func thePlaceIsWhatTheModelSees() {
        #expect(SuggestionMoment.place(of: composer()) == "Dear team,")
        let long = String(repeating: "word ", count: 200) + "end\nThanks for"
        let snapshot = composer(value: long)
        let place = SuggestionMoment.place(of: snapshot)
        #expect(place?.count == SuggestionMoment.precedingContextLength)
        #expect(place?.hasSuffix("end") == true)
        let situation = SuggestionMoment.situation(of: snapshot, surroundings: nil, recentLines: [])
        #expect(place == situation.preceding)
        #expect(SuggestionMoment.place(of: composer(value: "Thanks for")) == nil)
    }

    @Test("A window is one app's one document, whatever the field holds")
    func aWindowIsAnAppsDocument() {
        func field(
            _ bundle: String, _ document: String?, _ value: String,
            title: String? = nil, number: UInt32? = nil
        ) -> FocusedFieldSnapshot {
            FocusedFieldSnapshot(
                bundleIdentifier: bundle, applicationName: "App", role: "AXTextArea", document: document,
                value: value, windowTitle: title, windowNumber: number)
        }
        let key = SuggestionMoment.windowKey(of: field("com.example.mail", "draft", "Hi"))
        #expect(key == SuggestionMoment.windowKey(of: field("com.example.mail", "draft", "Hi there")))
        #expect(key != SuggestionMoment.windowKey(of: field("com.example.mail", "reply", "Hi")))
        #expect(key != SuggestionMoment.windowKey(of: field("com.example.notes", "draft", "Hi")))
        #expect(
            SuggestionMoment.windowKey(of: field("com.example.mail", nil, "Hi"))
                != SuggestionMoment.windowKey(of: field("com.example.mail", "draft", "Hi")))
        let titled = SuggestionMoment.windowKey(
            of: field("com.example.mail", "draft", "Hi", title: "Re: plans", number: 3))
        #expect(key != titled)
        #expect(
            titled
                != SuggestionMoment.windowKey(
                    of: field("com.example.mail", "draft", "Hi", title: "Re: roadmap", number: 3)))
        #expect(
            SuggestionMoment.windowKey(
                of: field("com.example.mail", "draft", "Hi", title: "Re: plans", number: 3))
                != SuggestionMoment.windowKey(
                    of: field("com.example.mail", "draft", "Hi", title: "Re: plans", number: 4)))
    }

    @Test("A conversation title change does not reuse another window's surroundings")
    func titleChangeWalksTheNewWindow() async {
        let cache = SuggestionContextCache()
        let first = FocusedFieldSnapshot(
            bundleIdentifier: "com.example.mail", applicationName: "Mail", role: "AXTextArea",
            document: nil, windowTitle: "Conversation A")
        let second = FocusedFieldSnapshot(
            bundleIdentifier: "com.example.mail", applicationName: "Mail", role: "AXTextArea",
            document: nil, windowTitle: "Conversation B")

        _ = await cache.surroundings(for: SuggestionMoment.windowKey(of: first)) {
            Surroundings(windowTitle: "Conversation A", text: "Message from A")
        }
        let secondAround = await cache.surroundings(for: SuggestionMoment.windowKey(of: second)) {
            Surroundings(windowTitle: "Conversation B", text: "Message from B")
        }

        #expect(secondAround?.windowTitle == "Conversation B")
        #expect(secondAround?.text == "Message from B")
    }
}
