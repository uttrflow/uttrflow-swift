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

    @Test("records which pass removed the word")
    func provenance() {
        let draft = sut.apply(Draft(text: "um hello"))
        #expect(draft.words[0].state == .removed(by: FillersPass.id))
        #expect(draft.words[1].state == .kept)
        #expect(draft.originalText == "um hello")
    }
}
