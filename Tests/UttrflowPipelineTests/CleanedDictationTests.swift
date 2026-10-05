import Foundation
import Testing

@testable import UttrflowAI
@testable import UttrflowCore
@testable import UttrflowDictionary
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

@Suite("Cleaning recognised pieces without recording")
struct CleanedDictationTests {
    private static let entry = DictionaryEntry(
        word: "Uttrflow", pronunciation: "utter flow", origin: .added, firstSeen: .distantPast)

    private func pipeline(knowing entries: [DictionaryEntry] = []) -> DictationPipeline {
        let index = PhoneticIndex(entries: entries)
        let router = TransformerRouter(
            engines: [RuleBasedTransformer()], preference: [.rules], rulesAlone: .shortReplies)
        return DictationPipeline(
            capture: FakeAudioCaptureEngine(), speech: FakeSpeechEngine(), cleaner: router,
            context: FakeContextEngine(), inserter: FakeTextInserter(),
            corrector: DictionaryCorrections { index })
    }

    /// A transcript scored word by word, a word marked `?` doubted at the confidence the recogniser gives a guess.
    private func scored(_ marked: String) -> Transcription {
        let words = marked.split(separator: " ").map {
            TranscribedWord(
                text: $0.replacingOccurrences(of: "?", with: ""), confidence: $0.hasPrefix("?") ? 0.2 : 1)
        }
        let text = words.map(\.text).joined(separator: " ")
        return Transcription(
            text: text, segments: [TranscriptionSegment(text: text, start: .zero, end: .zero, words: words)])
    }

    @Test("each piece is reported as tidied, and the joined text is what one dictation of them writes")
    func piecesAndWhole() async {
        let cleaned = await pipeline().clean(
            [Transcription(text: "four hundred"), Transcription(text: "and twenty dollars")],
            seeing: AppContext())

        #expect(cleaned.pieces == ["400", "and 20 dollars"])
        #expect(cleaned.text?.hasPrefix("400") == true)
    }

    @Test("a dictionary word split by a pause is corrected across the seam")
    func dictionaryAcrossSeam() async {
        let cleaned = await pipeline(knowing: [Self.entry]).clean(
            [
                scored("Uttrflow works offline and the whole point of ?utter"),
                scored("?flow is that nothing leaves the Mac"),
            ], seeing: AppContext())

        #expect(cleaned.text?.contains("point of Uttrflow is") == true)
        #expect(cleaned.pieces.allSatisfy { !$0.contains("of Uttrflow") })
    }

    @Test("the dictionary corrects a doubted run and leaves an unscored transcript alone")
    func dictionaryNeedsScores() async {
        let corrector = DictionaryCorrections { PhoneticIndex(entries: [Self.entry]) }

        let said = "Uttrflow works offline and the whole point of ?utter ?flow is that nothing leaves the Mac"
        let heard = await corrector.corrections(for: scored(said), seeing: AppContext())
        let unscored = await corrector.corrections(
            for: Transcription(text: said.replacingOccurrences(of: "?", with: "")), seeing: AppContext())

        #expect(heard.map(\.wrote) == ["Uttrflow"])
        #expect(unscored.isEmpty)
    }

    @Test("nothing writable is reported as no text, as a dictation refuses silence")
    func nothingWritable() async {
        let cleaned = await pipeline().clean([Transcription(text: "...")], seeing: AppContext())

        #expect(cleaned.text == nil)
    }
}
