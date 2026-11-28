import Foundation
import Testing

@testable import UttrflowAI
@testable import UttrflowCore
@testable import UttrflowDictionary
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

@Suite("A pause after a subordinate clause's subject, before its verb, writes what one piece does")
struct ClauseVerbSeamTests {
    private let pipeline: DictationPipeline = {
        let router = TransformerRouter(
            engines: [RuleBasedTransformer()], preference: [.rules], clock: ManualClock())
        return DictationPipeline(
            capture: FakeAudioCaptureEngine(), speech: FakeSpeechEngine(), cleaner: router,
            context: FakeContextEngine(), inserter: FakeTextInserter(),
            corrector: DictionaryCorrections { _ in PhoneticIndex(entries: []) })
    }()

    static let cuts: [SeamCut] = [
        SeamCut(pieces: ["Call me when you", "Get there"], whole: "Call me when you get there"),
        SeamCut(pieces: ["Call me when the build", "Is done"], whole: "Call me when the build is done"),
        SeamCut(pieces: ["Tell me if she", "Can come"], whole: "Tell me if she can come"),
        SeamCut(
            pieces: ["Call me when you arrive", "Then we eat"], whole: "Call me when you arrive. Then we eat"),
    ]

    @Test("a seam inside a subordinate clause that has no verb yet runs on", arguments: cuts)
    func seamMatchesWhole(_ cut: SeamCut) async {
        let joined = await written(cut.pieces)
        let whole = await written([cut.whole])
        #expect(joined == whole)
    }

    private func written(_ pieces: [String]) async -> String? {
        await pipeline.clean(pieces.map { Transcription(text: $0) }, seeing: AppContext()).text
    }
}
