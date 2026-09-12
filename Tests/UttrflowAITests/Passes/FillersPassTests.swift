import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("FillersPass")
struct FillersPassTests {
    private let sut = FillersPass()

    @Test(
        "removes the sounds people make while thinking",
        arguments: [
            ("um hello there", "hello there"),
            ("hello uh there", "hello there"),
            ("er hello", "hello"),
            ("hello there hmm", "hello there"),
            ("Um, hello", "hello"),
            ("uh um er hello", "hello"),
            ("aah ahh mhm okay", "okay"),
            ("hmm? yes", "yes"),
        ]
    )
    func removesFillers(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "keeps words that only sometimes act as filler",
        arguments: [
            "I would like a coffee",
            "well done everyone",
            "so the answer is four",
            "you know the answer",
            "basically that is a hard problem",
            "the umbrella is in the hall",
            "uh-oh",
            "um2 is a label",
            // "mm" is millimetres, and "MM" is millions.
            "the gap is three mm",
            "revenue of 4 MM",
        ]
    )
    func keepsAmbiguousWords(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    /// A determiner before it says the token is a noun, which is what tells "the ER" from a hesitation.
    @Test(
        "keeps a word a determiner opens, however it is spelled",
        arguments: [
            "I took her to the ER", "an ER visit ran long", "her ER shift",
            "we waited in the ER for hours", "put the ah file back",
            // An interior mark is part of the word, so this is not the filler spelling at all.
            "I took her to the E.R.",
        ]
    )
    func keepsANounADeterminerOpens(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    /// The guard reads one word back, so a filler that opens the text has nothing to be mentioned by.
    @Test("still removes a filler with no determiner before it")
    func removesAFillerWithNoDeterminer() {
        #expect(cleaned("Er, I think so", by: sut) == "I think so")
        #expect(cleaned("we waited er for hours", by: sut) == "we waited for hours")
    }

    @Test("records which pass removed the word")
    func provenance() {
        let draft = sut.apply(Draft(text: "um hello"))
        #expect(draft.words[0].state == .removed(by: FillersPass.id))
        #expect(draft.words[1].state == .kept)
        #expect(draft.originalText == "um hello")
    }

    /// The recogniser hangs the sentence's mark on the last word it heard, and that can be the filler.
    @Test(
        "keeps the mark the recogniser hung on a trailing filler",
        arguments: [
            ("so are we shipping today, uh?", "so are we shipping today?"),
            ("are we shipping today uh?", "are we shipping today?"),
            ("that is amazing uh!", "that is amazing!"),
            ("no way um!", "no way!"),
            // Nothing stands before it, so there is nowhere for the mark to go.
            ("hmm? yes", "yes"),
        ]
    )
    func keepsTheMarkOnATrailingFiller(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    /// Found by dictating it: "we should, uh, ship" left a comma separating nothing.
    @Test(
        "takes the comma that only bracketed the filler",
        arguments: [
            ("we should, uh, ship it", "we should ship it"),
            ("the build, um, failed", "the build failed"),
            // Only a bracketed one: a comma doing its own work stays.
            ("first, uh second", "first, second"),
            ("So um, I think we should", "So I think we should"),
        ]
    )
    func dropsTheBracketingComma(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }
}
