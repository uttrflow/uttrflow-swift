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
            ("no no no", "no"),
            ("The the plan", "The plan"),
            ("we we we should", "we should"),
        ]
    )
    func removesStammer(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
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
