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
}
