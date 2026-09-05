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

    @Test(
        "keeps a repeated long word, and a repeat split by punctuation",
        arguments: ["really really good", "had, had", "hello hello"]
    )
    func keepsRepeats(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    @Test("records which pass removed the word")
    func provenance() {
        let draft = sut.apply(Draft(text: "the the plan"))
        #expect(draft.words.map(\.state) == [.kept, .removed(by: StammersPass.id), .kept])
    }
}
