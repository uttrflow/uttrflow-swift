import Foundation
import Testing

@testable import UttrflowAI
@testable import UttrflowCore
@testable import UttrflowDictionary
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

@Suite("A pause before a conjunction, or after a written stop, writes what one piece does")
struct ConjunctionSeamTests {
    private let pipeline: DictationPipeline = {
        let router = TransformerRouter(engines: [RuleBasedTransformer()], preference: [.rules])
        return DictationPipeline(
            capture: FakeAudioCaptureEngine(), speech: FakeSpeechEngine(), cleaner: router,
            context: FakeContextEngine(), inserter: FakeTextInserter(),
            corrector: DictionaryCorrections { _ in PhoneticIndex(entries: []) })
    }()

    static let cuts: [SeamCut] = [
        SeamCut(
            pieces: ["it was raining", "so we stayed inside"], whole: "it was raining so we stayed inside"),
        SeamCut(
            pieces: ["no I don't think", "so we should wait for the results"],
            whole: "no I don't think so we should wait for the results"),
        SeamCut(
            pieces: ["logins need memory to be up", "so we add a health check"],
            whole: "logins need memory to be up so we add a health check"),
        SeamCut(
            pieces: ["I finished the report", "and Maria sent it on"],
            whole: "I finished the report and Maria sent it on"),
        SeamCut(
            pieces: ["My manager.", "Wants the slides by noon"],
            whole: "My manager. Wants the slides by noon"),
        SeamCut(
            pieces: ["the server.", "crashed twice last night"],
            whole: "the server. crashed twice last night"),
    ]

    @Test(
        "a seam with no stop runs on into a conjunction, and a written stop is judged as in one piece",
        arguments: cuts)
    func seamMatchesWhole(_ cut: SeamCut) async {
        let joined = await written(cut.pieces)
        let whole = await written([cut.whole])
        #expect(joined == whole)
    }

    private func written(_ pieces: [String]) async -> String? {
        await pipeline.clean(pieces.map { Transcription(text: $0) }, seeing: AppContext()).text
    }
}
