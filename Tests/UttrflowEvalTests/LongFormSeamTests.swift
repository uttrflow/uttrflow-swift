// Tests that a long dictation cut at its pauses is written with no seam artefact the one-pass text lacks.
import Testing
import UttrflowAI
import UttrflowCore
import UttrflowPipeline
import UttrflowTestSupport

@testable import UttrflowEval

@Suite("Long-form seams: cleaning the pieces cut at each pause writes the whole's stops, capitals and words")
struct LongFormSeamTests {
    /// The cases whose written pieces carry a seam artefact today; a fix that clears one removes it here.
    static let failingToday: [String: String] = [
        "long-form-rambling-email-two-topics": joinerStop,
        "long-form-listing-steps-by-ordinal": joinerStop,
    ]

    static let joinerStop =
        "the join ends a piece in a stop, and capitalises the next, where the one-piece text runs on"

    static let paused = EvaluationCorpus.longForm.filter { !$0.pausedAfter.isEmpty }

    @Test("each paused case's seams score nothing against it cleaned as one piece", arguments: paused)
    func seamsScoreNothing(_ testCase: EvaluationCase) async {
        let score = await Self.score(testCase)
        guard let reason = Self.failingToday[testCase.id] else {
            #expect(score.total == SeamTally(), "\(testCase.id): \(score.seams)")
            return
        }
        withKnownIssue(Comment(rawValue: reason)) { #expect(score.total == SeamTally()) }
    }

    /// The case's words cut after each paused word, cleaned and joined by the rules engine, scored against one piece.
    static func score(_ testCase: EvaluationCase) async -> SeamScore {
        let pipeline = DictationPipeline(
            capture: FakeAudioCaptureEngine(), speech: FakeSpeechEngine(),
            cleaner: TransformerRouter(
                engines: [RuleBasedTransformer()], preference: [.rules], clock: ManualClock()),
            context: FakeContextEngine(), inserter: FakeTextInserter(), clock: ManualClock())
        let words = testCase.spoken.split(whereSeparator: \.isWhitespace).map(String.init)
        var pieces: [Transcription] = []
        var start = 0
        for end in testCase.pausedAfter.sorted().map({ $0 + 1 }) + [words.count] where end > start {
            pieces.append(Transcription(text: words[start..<end].joined(separator: " ")))
            start = end
        }
        let whole = await pipeline.clean([Transcription(text: testCase.spoken)], seeing: testCase.context)
        let joined = await pipeline.clean(pieces, seeing: testCase.context)
        return SeamScore(whole: whole.text ?? "", written: joined.text ?? "", pieces: joined.pieces)
    }
}
