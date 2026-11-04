import Testing

@testable import UttrflowAI
@testable import UttrflowCore
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

@Suite("A number and the noun it counts across a pause")
struct PieceJoinerCountedNounTests {
    private func written(_ pieces: [String]) async -> String? {
        let router = TransformerRouter(
            engines: [RuleBasedTransformer()], preference: [.rules], rulesAlone: .shortReplies)
        let pipeline = DictationPipeline(
            capture: FakeAudioCaptureEngine(), speech: FakeSpeechEngine(), cleaner: router,
            context: FakeContextEngine(), inserter: FakeTextInserter())
        return await pipeline.clean(pieces.map { Transcription(text: $0) }, seeing: AppContext()).text
    }

    @Test(
        "keeps a number and the noun it counts in one phrase",
        arguments: [
            (["it costs twelve", "dollars"], "It costs 12 dollars."),
            (["it is thirty", "degrees"], "It is 30 degrees."),
            (["it weighs fifty", "kilos"], "It weighs 50 kilos."),
            (["it costs twelve dollars and fifty", "cents"], "It costs 12 dollars and 50 cents."),
            (["we need ten", "people"], "We need 10 people."),
            (["there were twenty", "chairs in the hall"], "There were 20 chairs in the hall."),
        ]
    )
    func numberTakesItsNoun(pieces: [String], expected: String) async {
        let text = await written(pieces)
        #expect(text == expected)
    }

    @Test(
        "still ends the sentence after a number that is not followed by what it counts",
        arguments: [
            (["it costs twelve", "we paid it"], "It costs 12. We paid it."),
            (["she is thirty", "friday we leave"], "She is 30. Friday we leave."),
            (["the answer is forty two", "then we left"], "The answer is 42. Then we left."),
        ]
    )
    func numberEndsTheSentence(pieces: [String], expected: String) async {
        let text = await written(pieces)
        #expect(text == expected)
    }
}
