import Testing

@testable import UttrflowAI
@testable import UttrflowCore
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

@Suite("A lone subject cut from its verb by a pause")
struct PieceJoinerLoneSubjectTests {
    private func written(_ pieces: [String]) async -> String? {
        let router = TransformerRouter(
            engines: [RuleBasedTransformer()], preference: [.rules], rulesAlone: .shortReplies)
        let pipeline = DictationPipeline(
            capture: FakeAudioCaptureEngine(), speech: FakeSpeechEngine(), cleaner: router,
            context: FakeContextEngine(), inserter: FakeTextInserter())
        return await pipeline.clean(pieces.map { Transcription(text: $0) }, seeing: AppContext()).text
    }

    @Test(
        "joins a subject pronoun or please to the verb after the pause",
        arguments: [
            (["she", "booked colon surgery for june"], "She booked colon surgery for June."),
            (["he", "has colon trouble again"], "He has colon trouble again."),
            (
                ["please", "fix comma placement in the second paragraph"],
                "Please fix comma placement in the second paragraph."
            ),
            (
                ["he keeps", "writing comma splices in every draft"],
                "He keeps writing comma splices in every draft."
            ),
        ]
    )
    func joinsLoneSubject(pieces: [String], expected: String) async {
        #expect(await written(pieces) == expected)
    }

    @Test(
        "joins a lone subject whose verb takes a pronoun object",
        arguments: [
            (["she", "told you about the booking"], "She told you about the booking."),
            (["please", "tell everyone about the booking"], "Please tell everyone about the booking."),
        ]
    )
    func joinsVerbWithPronounObject(pieces: [String], expected: String) async {
        #expect(await written(pieces) == expected)
    }

    @Test(
        "keeps the stop where the next piece asks or opens on a base verb that ends in ing",
        arguments: [
            (["please", "do you have it"], "Please. Do you have it?"),
            (["we sing", "bring the cake"], "We sing. Bring the cake."),
        ]
    )
    func keepsStopBeforeQuestionOrBaseVerb(pieces: [String], expected: String) async {
        let text = await written(pieces)
        #expect(text == expected)
    }
}
