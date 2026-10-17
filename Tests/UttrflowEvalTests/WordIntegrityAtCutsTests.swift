// Tests that cutting a long dictation anywhere never loses or doubles a spoken word.
import Testing
import UttrflowAI
import UttrflowCore
import UttrflowPipeline
import UttrflowTestSupport

@testable import UttrflowEval

@Suite("Word integrity at piece cuts: every spoken word appears once, in order, whatever the cut")
struct WordIntegrityAtCutsTests {
    /// What a cut left wrong about words: the seam's doubled and lost words, nothing else counted.
    struct Damage: Equatable, CustomStringConvertible {
        var duplicated = 0
        var dropped = 0
        var description: String { "duplicated \(duplicated), dropped \(dropped)" }
    }

    /// Every long-form case, whether or not the author marked a pause in it.
    static let cases = EvaluationCase.longFormCases

    /// The cases whose cut inside a spoken correction keeps the words the speaker took back.
    static let correctionSplitByCut: [String: String] = [
        "long-form-correcting-an-item-in-a-list": correctionSplit
    ]

    static let correctionSplit =
        "a cut inside a spoken correction's trigger leaves the words it replaces in the text"

    /// Cut at each word boundary alone (a pause can fall between any two words), including the natural pauses.
    @Test("a cut at any one word boundary writes every word once", arguments: cases)
    func anySingleCut(_ testCase: EvaluationCase) async {
        let count = testCase.spoken.split(whereSeparator: \.isWhitespace).count
        var failures: [String] = []
        for cut in 1..<max(count, 1) {
            let damage = await Self.damage(testCase, cuts: [cut])
            if damage != Damage() { failures.append("cut after word \(cut): \(damage)") }
        }
        guard let reason = Self.correctionSplitByCut[testCase.id] else {
            #expect(failures.isEmpty, "\(testCase.id): \(failures.prefix(5))")
            return
        }
        withKnownIssue(Comment(rawValue: reason)) { #expect(failures.isEmpty) }
    }

    /// The natural pauses and the forced cut together: every pause the author marked, plus one at the window's end.
    @Test("the marked pauses plus a forced cut write every word once", arguments: cases)
    func pausesAndForcedCut(_ testCase: EvaluationCase) async {
        let count = testCase.spoken.split(whereSeparator: \.isWhitespace).count
        let pauses = testCase.pausedAfter.map { $0 + 1 }
        let forced = count / 2
        let cuts = Set(pauses + [forced]).filter { $0 > 0 && $0 < count }.sorted()
        let damage = await Self.damage(testCase, cuts: cuts)
        #expect(damage == Damage(), "\(testCase.id) cuts \(cuts): \(damage)")
    }

    /// The case cut after the given word counts, cleaned and joined by the rules engine, scored against one piece.
    static func damage(_ testCase: EvaluationCase, cuts: [Int]) async -> Damage {
        let pipeline = DictationPipeline(
            capture: FakeAudioCaptureEngine(), speech: FakeSpeechEngine(),
            cleaner: TransformerRouter(
                engines: [RuleBasedTransformer()], preference: [.rules], clock: ManualClock()),
            context: FakeContextEngine(), inserter: FakeTextInserter(), clock: ManualClock())
        let words = testCase.spoken.split(whereSeparator: \.isWhitespace).map(String.init)
        var pieces: [Transcription] = []
        var start = 0
        for end in cuts + [words.count] where end > start {
            pieces.append(Transcription(text: words[start..<end].joined(separator: " ")))
            start = end
        }
        let whole = await pipeline.clean([Transcription(text: testCase.spoken)], seeing: testCase.context)
        let joined = await pipeline.clean(pieces, seeing: testCase.context)
        let score = SeamScore(whole: whole.text ?? "", written: joined.text ?? "", pieces: joined.pieces)
        return Damage(duplicated: score.total.duplicated, dropped: score.total.dropped)
    }
}

extension EvaluationCase {
    static var longFormCases: [EvaluationCase] { EvaluationCorpus.longForm }
}
