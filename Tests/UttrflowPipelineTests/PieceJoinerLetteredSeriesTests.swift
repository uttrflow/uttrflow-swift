import Testing

@testable import UttrflowAI
@testable import UttrflowCore
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

@Suite("A lettered item series cut by a pause")
struct PieceJoinerLetteredSeriesTests {
    private static let spoken =
        "clause nine point one the supplier shall item a deliver within thirty days of the order item b replace any damaged goods at its own cost and item c keep records for six years"
    private static let pages = AppContext(
        applicationName: "Pages", bundleIdentifier: "com.apple.iWork.Pages")

    private func written(_ pieces: [String]) async -> String? {
        let router = TransformerRouter(
            engines: [RuleBasedTransformer()], preference: [.rules], rulesAlone: .shortReplies)
        let pipeline = DictationPipeline(
            capture: FakeAudioCaptureEngine(), speech: FakeSpeechEngine(), cleaner: router,
            context: FakeContextEngine(), inserter: FakeTextInserter())
        return await pipeline.clean(pieces.map { Transcription(text: $0) }, seeing: Self.pages).text
    }

    @Test("writes every (a), (b), (c) line wherever the pause falls inside the series", arguments: 9...27)
    func cutAnywhereInTheSeries(cut: Int) async {
        let words = Self.spoken.split(separator: " ").map(String.init)
        let whole = await written([Self.spoken])
        let cutText = await written([
            words[..<cut].joined(separator: " "), words[cut...].joined(separator: " "),
        ])
        #expect(cutText == whole)
        #expect(whole?.contains("(c) keep records") == true)
    }

    @Test("does not read a series across a cut when the head opens none")
    func noSeriesNoJoin() {
        let formatter = DestinationFormatter.standard(
            for: Situation(app: .unknown, insertion: .unknown, destination: .document))
        let situation = Situation(app: .unknown, insertion: .unknown, destination: .document)
        #expect(
            !PieceJoiner.unitRunsAcross(
                "send the report today", into: "item b is late", under: formatter, going: situation))
    }
}
