// Tests for command scope: which span at the end of an inserted text each scope covers.

import Foundation
import Testing

@testable import UttrflowCore

@Suite("One command scope decides how much earlier text an edit covers")
struct CommandScopeTests {
    /// An inserted text and the span the word, clause and sentence scopes each cover at its end.
    struct Case: CustomTestStringConvertible, Sendable {
        let text: String
        let word: String
        let clause: String
        let sentence: String
        var testDescription: String { text }
    }

    static let cases: [Case] = [
        Case(text: "Send it today.", word: " today.", clause: "Send it today.", sentence: "Send it today."),
        Case(
            text: "Hi there. Send it today.", word: " today.", clause: " Send it today.",
            sentence: " Send it today."),
        Case(text: "One. Two. Three.", word: " Three.", clause: " Three.", sentence: " Three."),
        Case(
            text: "Is it ready? Tell me now.", word: " now.", clause: " Tell me now.",
            sentence: " Tell me now."),
        Case(text: "Great work! Ship it.", word: " it.", clause: " Ship it.", sentence: " Ship it."),
        Case(
            text: "The rate is 3.5 percent.", word: " percent.", clause: "The rate is 3.5 percent.",
            sentence: "The rate is 3.5 percent."),
        Case(
            text: "Done. The rate is 3.5 percent.", word: " percent.", clause: " The rate is 3.5 percent.",
            sentence: " The rate is 3.5 percent."),
        Case(
            text: "Bring fruit, e.g. apples.", word: " apples.", clause: " e.g. apples.",
            sentence: "Bring fruit, e.g. apples."),
        Case(
            text: "Fine. Bring fruit, e.g. Apples and pears.", word: " pears.",
            clause: " e.g. Apples and pears.",
            sentence: " Bring fruit, e.g. Apples and pears."),
        Case(
            text: "Use tools, i.e. hammers.", word: " hammers.", clause: " i.e. hammers.",
            sentence: "Use tools, i.e. hammers."),
        Case(
            text: "Ask Dr. Rao today.", word: " today.", clause: "Ask Dr. Rao today.",
            sentence: "Ask Dr. Rao today."),
        Case(
            text: "Hello. Ask Mr. Lee first.", word: " first.", clause: " Ask Mr. Lee first.",
            sentence: " Ask Mr. Lee first."),
        Case(
            text: "Open example.com now.", word: " now.", clause: "Open example.com now.",
            sentence: "Open example.com now."),
        Case(
            text: "Saved. Open https://example.com/a.b today.", word: " today.",
            clause: " Open https://example.com/a.b today.", sentence: " Open https://example.com/a.b today."),
        Case(
            text: "Mail ops@example.com. Then wait.", word: " wait.", clause: " Then wait.",
            sentence: " Then wait."),
        Case(
            text: "Buy milk, eggs, bread.", word: " bread.", clause: " bread.",
            sentence: "Buy milk, eggs, bread."),
        Case(
            text: "First: milk; then bread.", word: " bread.", clause: " then bread.",
            sentence: "First: milk; then bread."),
        Case(text: "Items:\n1. milk\n2. bread", word: " bread", clause: "\n2. bread", sentence: "\n2. bread"),
        Case(
            text: "Meet at 5 p.m. Bring snacks.", word: " snacks.", clause: " Bring snacks.",
            sentence: " Bring snacks."),
        Case(
            text: "Meet at 5 p.m. today.", word: " today.", clause: "Meet at 5 p.m. today.",
            sentence: "Meet at 5 p.m. today."),
        Case(
            text: "He works at Acme Inc. now.", word: " now.", clause: "He works at Acme Inc. now.",
            sentence: "He works at Acme Inc. now."),
        Case(
            text: "Fly to the U.S. Then rest.", word: " rest.", clause: " Then rest.", sentence: " Then rest."
        ),
        Case(
            text: "Pens, paper etc. are here.", word: " here.", clause: " paper etc. are here.",
            sentence: "Pens, paper etc. are here."),
        Case(
            text: "See No. 5 below.", word: " below.", clause: "See No. 5 below.",
            sentence: "See No. 5 below."),
        Case(
            text: "Kal milte hain. Theek hai?", word: " hai?", clause: " Theek hai?", sentence: " Theek hai?"),
        Case(
            text: "Main aa raha hoon, thoda late.", word: " late.", clause: " thoda late.",
            sentence: "Main aa raha hoon, thoda late."),
        Case(
            text: "Haan bhai. Meeting 3.30 pe hai.", word: " hai.", clause: " Meeting 3.30 pe hai.",
            sentence: " Meeting 3.30 pe hai."),
        Case(
            text: "Price is $4.99, sadly.", word: " sadly.", clause: " sadly.",
            sentence: "Price is $4.99, sadly."),
        Case(
            text: "Version 2.0.1 shipped.", word: " shipped.", clause: "Version 2.0.1 shipped.",
            sentence: "Version 2.0.1 shipped."),
        Case(
            text: "Wait\u{2026} really?", word: " really?", clause: "Wait\u{2026} really?",
            sentence: "Wait\u{2026} really?"),
        Case(text: "no stop here", word: " here", clause: "no stop here", sentence: "no stop here"),
        Case(text: "Done. no stop here", word: " here", clause: " no stop here", sentence: " no stop here"),
        Case(text: "word", word: "word", clause: "word", sentence: "word"),
        Case(
            text: "Trailing space. ", word: " space. ", clause: "Trailing space. ",
            sentence: "Trailing space. "),
        Case(
            text: "  Lead.  Two  spaces.", word: "  spaces.", clause: "  Two  spaces.",
            sentence: "  Two  spaces."),
        Case(text: "He said \"go.\" She left.", word: " left.", clause: " She left.", sentence: " She left."),
        Case(text: "Call me (later). Thanks.", word: " Thanks.", clause: " Thanks.", sentence: " Thanks."),
        Case(
            text: "Note \u{2014} this matters.", word: " matters.", clause: " this matters.",
            sentence: "Note \u{2014} this matters."),
        Case(text: "Room 4.5, floor 2.", word: " 2.", clause: " floor 2.", sentence: "Room 4.5, floor 2."),
        Case(text: "Yes. No. Maybe, later.", word: " later.", clause: " later.", sentence: " Maybe, later."),
    ]

    @Test("each scope covers the expected span at the end", arguments: cases)
    func resolves(_ example: Case) throws {
        for (scope, expected) in [
            (CommandScope.word, example.word), (.clause, example.clause), (.sentence, example.sentence),
        ] {
            let range = try #require(scope.range(in: example.text))
            #expect(String(example.text[range]) == expected, "\(scope)")
        }
        for scope in [CommandScope.piece, .dictation] {
            #expect(scope.range(in: example.text) == example.text.startIndex..<example.text.endIndex)
        }
    }

    @Test("the table holds forty invented texts")
    func tableSize() {
        #expect(Self.cases.count == 40)
    }

    @Test("a last sentence never splits a decimal or a lead-in abbreviation")
    func neverSplitsInsideAWord() throws {
        for text in ["Pay 3.5 now.", "Take one, e.g. this.", "Wait. Pay 3.5 now, e.g. cash."] {
            let range = try #require(CommandScope.sentence.range(in: text))
            let covered = String(text[range]).trimmingCharacters(in: .whitespaces)
            #expect(!covered.hasPrefix("5") && !covered.hasPrefix("g."), "\(text)")
        }
    }

    @Test("an empty or blank text refuses every scope", arguments: CommandScope.allCases)
    func refusesEmpty(_ scope: CommandScope) {
        #expect(scope.range(in: "") == nil)
        #expect(scope.range(in: "  \n ") == nil)
    }

    @Test("a bare command means the last dictation")
    func defaultScope() {
        #expect(CommandScope.default == .dictation)
    }
}
