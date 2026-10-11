import Foundation
import Testing
import UttrflowCore

@testable import UttrflowPredict

/// An editor, where a user may choose a word key.
private let editor = Surface(bundleIdentifier: "com.example.editor", role: "AXTextArea")

private let wordStroke = KeyStroke(.rightArrow, modifiers: .option)

@Suite("Taking the next word of a suggestion")
struct WordAcceptanceTests {
    @Test(
        "The next word comes with the space that leads it.",
        arguments: [
            ("Thanks for", "Thanks for your help today", "Thanks for your"),
            ("Thanks for ", "Thanks for your help today", "Thanks for your"),
            ("Thanks fo", "Thanks for your help today", "Thanks for"),
            ("Hi", "Hi, how are you", "Hi,"),
        ])
    func nextWord(typed: String, line: String, expected: String) {
        #expect(WordAcceptance.next(of: line, after: typed) == expected)
    }

    @Test("The last word is the whole line, so there is no smaller step to take.")
    func lastWord() {
        #expect(WordAcceptance.next(of: "Thanks for your", after: "Thanks for") == nil)
        #expect(WordAcceptance.next(of: "Thanks", after: "Than") == nil)
    }

    @Test("A line that rewrites what was typed is taken whole.")
    func replacement() {
        #expect(WordAcceptance.next(of: "Thanks for your help", after: "Thnks") == nil)
    }
}

@Suite("The word key is the user's own choice")
struct WordKeyRoutingTests {
    @Test("Without a chosen key the stroke is the application's and is never armed.")
    func unchosen() {
        let line = Suggestion.certain("one two three")
        #expect(KeyRouting.decision(for: wordStroke, showing: line) == .passThrough)
        #expect(!KeyRouting.arming(showing: line).contains(.optionRightArrow))
    }

    @Test("A chosen key takes the next word and is armed with it.", arguments: WordAcceptKey.allCases)
    func chosen(key: WordAcceptKey) {
        let line = Suggestion.certain("one two three")
        #expect(
            KeyRouting.decision(for: key.stroke, showing: line, wordKey: key)
                == .acceptWord("one two three"))
        let armed = KeyRouting.arming(showing: line, wordKey: key)
        #expect(armed.contains(ArmedKeys.takenSlot(of: key.stroke)))
        #expect(armed.contains(.tab))
    }

    @Test("A chosen key never moves the other key's slot.")
    func otherKeyStaysTheApplications() {
        let line = Suggestion.certain("one two three")
        let other = KeyStroke(.rightArrow, modifiers: .command)
        #expect(
            KeyRouting.decision(for: other, showing: line, wordKey: .optionRightArrow) == .passThrough)
    }

    @Test("The mask and the rules agree for every stroke.", arguments: WordAcceptKey.allCases)
    func maskAgrees(key: WordAcceptKey) {
        let line = Suggestion.choice(leader: "one two", others: ["one three"])
        let armed = KeyRouting.arming(showing: line, wordKey: key)
        for entry in ArmedKeys.slots + ArmedKeys.wordSlots {
            let decided = KeyRouting.decision(for: entry.stroke, showing: line, wordKey: key)
            #expect(armed.contains(entry.slot) == (decided != .passThrough))
        }
    }

    @Test("Each stroke occupies its own slot.")
    func slots() {
        #expect(ArmedKeys.takenSlot(of: wordStroke) == .optionRightArrow)
        #expect(ArmedKeys.takenSlot(of: KeyStroke(.rightArrow, modifiers: .command)) == .commandRightArrow)
        #expect(ArmedKeys.takenSlot(of: KeyStroke(.tab)) == .tab)
        #expect(ArmedKeys.takenSlot(of: KeyStroke(.rightArrow, modifiers: .control)).isEmpty)
        #expect(ArmedKeys.stroke(of: .commandRightArrow) == KeyStroke(.rightArrow, modifiers: .command))
    }
}

@Suite("A session taking one word at a time")
struct WordAcceptSessionTests {
    private func drawn(_ session: inout SuggestionSession) throws {
        _ = try draw(
            &session, typing: "Thanks for",
            candidates: [remembered("Thanks for your help today", count: 40)], in: editor,
            wordKey: .optionRightArrow)
    }

    @Test("A word is taken, the rest comes back as the offer, and nothing is rejected.")
    func takesAWordAndKeepsTheRest() throws {
        var session = SuggestionSession()
        try drawn(&session)
        #expect(session.route(wordStroke) == .acceptWord("Thanks for your"))
        // The field now holds the word; the next read offers the rest again with no question to the store.
        let turn = session.turn(
            in: editor, at: PredictionContext(typed: "Thanks for your"), wordKey: .optionRightArrow)
        #expect(turn.rejected == nil)
        guard case .settled(let update) = turn.step else {
            Issue.record("expected the remainder to be offered without a query")
            return
        }
        #expect(update.suggestion == .certain("Thanks for your help today"))
        #expect(session.route(wordStroke) == .acceptWord("Thanks for your help"))
    }

    @Test("The last word is a full acceptance.")
    func lastWordIsWhole() throws {
        var session = SuggestionSession()
        _ = try draw(
            &session, typing: "Thanks for", candidates: [remembered("Thanks for your", count: 40)],
            in: editor, wordKey: .optionRightArrow)
        #expect(session.route(wordStroke) == .accept("Thanks for your"))
    }

    @Test("Typing something else forgets the remainder.")
    func typingOnForgets() throws {
        var session = SuggestionSession()
        try drawn(&session)
        _ = session.route(wordStroke)
        let turn = session.turn(
            in: editor, at: PredictionContext(typed: "Thanks for you"), wordKey: .optionRightArrow)
        #expect(session.retained == nil)
        guard case .query = turn.step else {
            Issue.record("expected a fresh question")
            return
        }
    }

    @Test("A refused insertion forgets the remainder.")
    func refusedForgets() throws {
        var session = SuggestionSession()
        try drawn(&session)
        _ = session.route(wordStroke)
        session.completeAcceptance(.refused)
        #expect(session.retained == nil)
    }

    @Test("Whole acceptance still works beside the word key.")
    func tabStillTakesAll() throws {
        var session = SuggestionSession()
        try drawn(&session)
        #expect(session.route(KeyStroke(.tab)) == .accept("Thanks for your help today"))
        #expect(session.retained == nil)
    }
}

@Suite("Choosing a word key per application")
struct WordAcceptPreferencesTests {
    @Test("No application has a word key until one is chosen.")
    func none() {
        #expect(SuggestionPreferences.default.wordAcceptKey(forBundleIdentifier: "com.example.editor") == nil)
    }

    @Test("A choice is kept per application, in any case, and can be cleared.")
    func choose() throws {
        var preferences = SuggestionPreferences.default
        preferences.setWordAcceptKey(.optionRightArrow, in: "COM.Example.Editor")
        #expect(preferences.wordAcceptKey(forBundleIdentifier: "com.example.editor") == .optionRightArrow)
        let decoded = try JSONDecoder().decode(
            SuggestionPreferences.self, from: JSONEncoder().encode(preferences))
        #expect(decoded == preferences)
        preferences.setWordAcceptKey(nil, in: "com.example.editor")
        #expect(preferences.wordAcceptKey(forBundleIdentifier: "com.example.editor") == nil)
    }

    @Test("An unreadable choice falls back to none.")
    func unreadable() throws {
        let json = #"{"chosenWordAcceptKeys":{"com.example.editor":"nonsense"}}"#
        let decoded = try JSONDecoder().decode(SuggestionPreferences.self, from: Data(json.utf8))
        #expect(decoded.wordAcceptKey(forBundleIdentifier: "com.example.editor") == nil)
    }
}
