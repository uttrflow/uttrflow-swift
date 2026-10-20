// Tests for the count-and-noun helper the clip summary, the typing error and the page labels share.
import Testing

@testable import UttrflowCore

@Suite("CountedNoun")
struct CountedNounTests {
    @Test("the noun is singular at one and plural at zero and above one")
    func nouns() {
        #expect(CountedNoun.of(0, "piece", "pieces") == "pieces")
        #expect(CountedNoun.of(1, "piece", "pieces") == "piece")
        #expect(CountedNoun.of(2, "piece", "pieces") == "pieces")
        #expect(CountedNoun.of(1, "day", "days") == "day")
    }

    @Test("the phrase carries the count and its noun together")
    func phrases() {
        #expect(CountedNoun.count(1, "character", "characters") == "1 character")
        #expect(CountedNoun.count(405, "character", "characters") == "405 characters")
        #expect(CountedNoun.count(0, "character", "characters") == "0 characters")
    }

    @Test("a typing error that stopped inside one character says character")
    func insertionMessage() {
        #expect(
            TextInsertionError.insertionInterrupted(typed: 0, total: 1).userMessage
                == "Typing stopped after 0 of 1 character. Your dictation is saved under Recent in the menu bar."
        )
        #expect(
            TextInsertionError.insertionInterrupted(typed: 1, total: 2).userMessage
                == "Typing stopped after 1 of 2 characters. Your dictation is saved under Recent in the menu bar."
        )
    }
}
