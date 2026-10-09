import Foundation
import Testing

@testable import UttrflowAI
@testable import UttrflowCore
@testable import UttrflowDictionary
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

@Suite("Tracing a dictation's pieces and their join")
struct PieceTraceTests {
    private static let entry = DictionaryEntry(
        word: "Uttrflow", pronunciation: "utter flow", origin: .added, firstSeen: .distantPast)

    private func pipeline(knowing entries: [DictionaryEntry] = []) -> DictationPipeline {
        let index = PhoneticIndex(entries: entries)
        return DictationPipeline(
            capture: FakeAudioCaptureEngine(), speech: FakeSpeechEngine(),
            cleaner: TransformerRouter(engines: [RuleBasedTransformer()], preference: [.rules]),
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

    @Test("a replayed seam cut shows the stop the join writes, which neither piece nor the whole has")
    func seamStop() async {
        let pieces = [Transcription(text: "the team"), Transcription(text: "actually shipped the release")]
        let trace = await pipeline().trace(pieces, seeing: AppContext())
        let whole = await pipeline().clean(
            [Transcription(text: "the team actually shipped the release")], seeing: AppContext())

        #expect(
            trace.lines == [
                "piece 1    the team", "tidied by  rules", "tidied     the team",
                "piece 2    actually shipped the release", "tidied by  rules",
                "tidied     actually shipped the release",
                "joined     the team. actually shipped the release",
                "message    The team. Actually shipped the release.",
                "result     The team. Actually shipped the release.",
            ])
        #expect(trace.text == (await pipeline().clean(pieces, seeing: AppContext())).text)
        #expect(whole.text == "The team actually shipped the release.")
    }

    @Test("a number cut by a pause is shown tidied again as one piece before the join")
    func rejoinedUnit() async {
        let trace = await pipeline().trace(
            [Transcription(text: "four hundred"), Transcription(text: "and twenty dollars")],
            seeing: AppContext())

        #expect(trace.lines.contains("rejoined   420 dollars"))
        #expect(trace.lines.contains("tidied     400"))
    }

    @Test("a dictionary word split by a pause is shown corrected at the seam, after the join")
    func correctedAtSeam() async {
        let trace = await pipeline(knowing: [Self.entry]).trace(
            [
                scored("Uttrflow works offline and the whole point of ?utter"),
                scored("?flow is that nothing leaves the Mac"),
            ], seeing: AppContext())

        let atSeams = trace.lines.first { $0.hasPrefix("at seams") }
        #expect(atSeams?.contains("point of Uttrflow is") == true)
        #expect(trace.lines.first { $0.hasPrefix("joined") }?.contains("Uttrflow is") == false)
    }

    @Test("a word the dictionary moves inside a piece is shown before that piece is tidied")
    func correctedInPiece() async {
        let trace = await pipeline(knowing: [Self.entry]).trace(
            [scored("Uttrflow works offline and the whole point of ?utter ?flow is privacy")],
            seeing: AppContext())

        #expect(
            trace.lines.contains(
                "dictionary Uttrflow works offline and the whole point of Uttrflow is privacy"))
    }

    @Test("nothing writable is traced as such, as a dictation refuses silence")
    func nothingWritable() async {
        let trace = await pipeline().trace([Transcription(text: "...")], seeing: AppContext())

        #expect(trace.text == nil)
        #expect(trace.lines.last == "result     nothing writable")
    }
}
