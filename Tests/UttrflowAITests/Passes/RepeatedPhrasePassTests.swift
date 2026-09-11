import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("RepeatedPhrasePass")
struct RepeatedPhrasePassTests {
    private let sut = RepeatedPhrasePass()

    @Test(
        "removes a run of two to four words said twice in a row",
        arguments: [
            ("so I was I was thinking", "so I was thinking"),
            ("we need to we need to ship", "we need to ship"),
            ("I think that we I think that we should", "I think that we should"),
            ("so I was i Was thinking", "so i Was thinking"),
            ("I was I was I was thinking", "I was thinking"),
            ("can you can you send it", "can you send it"),
        ]
    )
    func removesRepeats(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "leaves single words, and a repeat with punctuation inside it",
        arguments: [
            "very very good",
            "the the plan",
            "I was, I was thinking",
            "it is what it is",
            "we did what we did",
        ]
    )
    func keeps(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    /// A run of numbers said twice spells one value, so taking a copy out changes the number.
    @Test(
        "keeps a repeated run of numbers, which is a value rather than a restart",
        arguments: [
            "the pin is four seven four seven",
            "dial 4 7 4 7 now",
            "the card starts four two four two four two four two",
            "extension one two one two",
        ]
    )
    func keepsRepeatedNumbers(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    @Test("still removes a restart that merely has a number in it")
    func removesARestartWithANumberInIt() {
        #expect(cleaned("call me at five call me at five today", by: sut) == "call me at five today")
    }

    @Test("reads a run as a value only when every word of it is a number")
    func numberRuns() {
        #expect(NumberWords.isNumberRun(["four", "seven"]))
        #expect(NumberWords.isNumberRun(["4", "7", "twenty"]))
        #expect(!NumberWords.isNumberRun(["at", "five"]))
        #expect(!NumberWords.isNumberRun([String]()))
    }

    @Test("drops the first copy and keeps the second")
    func provenance() {
        let draft = sut.apply(Draft(text: "so I was I was thinking"))
        #expect(draft.words.map(\.isPresent) == [true, false, false, true, true, true])
        #expect(draft.removed.allSatisfy { $0.state == .removed(by: RepeatedPhrasePass.id) })
    }
}
