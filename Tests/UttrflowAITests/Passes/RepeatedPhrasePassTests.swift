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

    /// A run said twice on purpose is a name or an emphasis, and half of it is a word the speaker meant.
    @Test(
        "keeps a run repeated on purpose rather than restarted",
        arguments: [
            "ha ha ha ha",
            "no no no no",
            "New York New York is the song",
            "we flew to Bora Bora Bora Bora",
            "the code is s w one a one a a",
            "press one two one two to confirm",
        ]
    )
    func keepsDeliberateRepeat(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    @Test(
        "keeps deliberate intensifier and continuation chains",
        arguments: [
            "it went on and on and on",
            "it went on and on and on and on and on",
            "again and again and again",
            "again and again and again and again and again",
            "more and more and more",
            "more and more and more and more and more",
            "blah blah blah and so on and so on",
            "and so on and so on and so on and so on",
        ]
    )
    func keepsDeliberateChains(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    @Test("the standard pipeline keeps every word in a deliberate continuation")
    func standardPipelineKeepsChain() async throws {
        let request = TransformationRequest(
            transcription: Transcription(text: "it went on and on and on and on and on"),
            context: .unknown)
        let result = try await RuleBasedTransformer().transform(request)
        #expect(result.text == "It went on and on and on and on and on.")
    }

    @Test("drops the first copy and keeps the second")
    func provenance() {
        let draft = sut.apply(Draft(text: "so I was I was thinking"))
        #expect(draft.words.map(\.isPresent) == [true, false, false, true, true, true])
        #expect(draft.removed.allSatisfy { $0.state == .removed(by: RepeatedPhrasePass.id) })
    }
}
