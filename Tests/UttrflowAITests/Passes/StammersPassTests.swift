import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("StammersPass")
struct StammersPassTests {
    private let sut = StammersPass()

    @Test(
        "removes the doubled short word a false start leaves behind",
        arguments: [
            ("the the deployment", "the deployment"),
            ("I I think so", "I think so"),
            ("The the plan", "The plan"),
            ("we we we should", "we should"),
            ("the build is is red", "the build is red"),
        ]
    )
    func removesStammer(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    /// "this" and "what" are function words, so the restart reading wins over the emphatic one by design.
    @Test(
        "still removes a doubled function word English also emphasises",
        arguments: [
            ("this this thing is broken", "this thing is broken"),
            ("what what did you say", "what did you say"),
        ]
    )
    func removesDoubledFunctionWordDespiteEmphaticReading(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    /// A double English means is not a stammer, and taking a word out of one loses what was said.
    @Test(
        "keeps a double the language itself makes",
        arguments: [
            "I had had enough by then",
            "the thing that that person said",
            "bye bye for now",
            "no no no",
            "the soup was so so",
        ]
    )
    func keepsLegitimateDoubles(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    /// A number said twice is two digits of one value, so taking one out changes the number.
    @Test(
        "keeps a repeated number word, which spells a digit rather than stammering",
        arguments: ["extension four four two", "port eight zero zero zero", "the code is one one one"]
    )
    func keepsRepeatedNumbers(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    @Test(
        "keeps a repeated long word, and a repeat split by punctuation",
        arguments: ["really really good", "had, had", "hello hello"]
    )
    func keepsRepeats(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    /// English repeats a short word for emphasis as readily as a long one, and both halves were meant.
    @Test(
        "keeps a short word repeated for emphasis",
        arguments: [
            "this is very very important",
            "much much better",
            "okay okay I hear you",
            "hear hear",
            "chop chop",
        ]
    )
    func keepsEmphaticRepeat(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    /// A doubled name loses half of itself to a removal, and no list of exceptions reaches every name.
    @Test(
        "keeps a doubled proper noun",
        arguments: ["we flew to Bora Bora last year", "the flight to Pago Pago"]
    )
    func keepsDoubledName(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    /// A third copy is matched against the same stale previous word, so the run collapses to one token.
    @Test("keeps every copy of a word said three times for emphasis")
    func keepsTripledEmphasis() {
        #expect(cleaned("ha ha ha", by: sut) == "ha ha ha")
    }

    @Test("records which pass removed the word")
    func provenance() {
        let draft = sut.apply(Draft(text: "the the plan"))
        #expect(draft.words.map(\.state) == [.kept, .removed(by: StammersPass.id), .kept])
    }
}
