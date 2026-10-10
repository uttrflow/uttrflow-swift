import Foundation
import Testing
import UttrflowCore
@testable import UttrflowPipeline

@Suite struct DoubtfulWordsLocatingTests {
    /// A transcription scored word by word; a word named in `doubted` scores 0.2, every other 0.95.
    private func heard(_ text: String, doubted: Set<String> = [], settled: Set<String> = []) -> Transcription
    {
        let words = text.split(separator: " ").map { word in
            TranscribedWord(
                text: String(word), confidence: doubted.contains(String(word)) ? 0.2 : 0.95,
                settled: settled.contains(String(word)))
        }
        return Transcription(
            text: text,
            segments: [TranscriptionSegment(text: text, start: .zero, end: .seconds(5), words: words)])
    }

    private func spans(_ doubtful: DoubtfulWordsOutcome) -> [DoubtfulWordSpan] {
        guard case .placed(let spans, _) = doubtful else { return [] }
        return spans
    }

    @Test func aFillerTheTidierRemovedLeavesTheDoubtedWordOnItsWrittenPlace() {
        let doubtful = DoubtfulWordsOutcome.locating(
            heard("um send the reprot today", doubted: ["reprot"]), in: "Send the report today.")
        #expect(
            doubtful == .placed([DoubtfulWordSpan(range: 2..<3, kind: .lowScore, evidence: 0)], unplaced: 0))
    }

    @Test func aDoubtedFillerThatWasRemovedIsCountedUnplaced() {
        let doubtful = DoubtfulWordsOutcome.locating(heard("um send it", doubted: ["um"]), in: "Send it.")
        #expect(doubtful == .placed([], unplaced: 1))
    }

    @Test func aRewrittenNumberIsNumberLikeOnTheDigits() {
        let doubtful = DoubtfulWordsOutcome.locating(
            heard("meet at five today", doubted: ["five"]), in: "Meet at 5 today.")
        #expect(
            spans(doubtful) == [DoubtfulWordSpan(range: 2..<3, kind: .numberLike, evidence: 0)])
    }

    @Test func aDictionaryOverrideIsOverriddenWhereverItLanded() {
        let doubtful = DoubtfulWordsOutcome.locating(
            heard("ask uttrflow team now", settled: ["uttrflow"]), in: "Ask Uttrflow team now.")
        #expect(spans(doubtful) == [DoubtfulWordSpan(range: 1..<2, kind: .overridden, evidence: 3)])
    }

    @Test func aModelRewriteOfADoubtedWordIsPlacedOnTheRewrite() {
        let doubtful = DoubtfulWordsOutcome.locating(
            heard("i want to by milk", doubted: ["by"]), in: "I want to buy milk.")
        #expect(
            spans(doubtful) == [
                DoubtfulWordSpan(range: 2..<3, kind: .soundAlikeClass, evidence: 3),
                DoubtfulWordSpan(range: 3..<4, kind: .lowScore, evidence: 0),
            ])
    }

    @Test func aSurelyHeardSoundAlikeIsTheSoundAlikeKind() {
        let doubtful = DoubtfulWordsOutcome.locating(
            heard("put it there please"), in: "Put it there, please.")
        #expect(spans(doubtful) == [DoubtfulWordSpan(range: 2..<3, kind: .soundAlikeClass, evidence: 3)])
    }

    @Test func aDoubtedWordBesideANegatorIsNegatorAdjacent() {
        let doubtful = DoubtfulWordsOutcome.locating(
            heard("do not delpoy today", doubted: ["delpoy"]), in: "Do not deploy today.")
        #expect(spans(doubtful) == [DoubtfulWordSpan(range: 2..<3, kind: .negatorAdjacent, evidence: 0)])
    }

    @Test func aDoubtedWordWrittenAsANameIsNameLike() {
        let doubtful = DoubtfulWordsOutcome.locating(
            heard("call jorna today", doubted: ["jorna"]), in: "Call Jorna today.")
        #expect(spans(doubtful) == [DoubtfulWordSpan(range: 1..<2, kind: .nameLike, evidence: 0)])
    }

    @Test func neighbouringDoubtsOfOneKindAreOneSpan() {
        let doubtful = DoubtfulWordsOutcome.locating(
            heard("the quarck blorp ran", doubted: ["quarck", "blorp"]), in: "The quarck blorp ran.")
        #expect(spans(doubtful) == [DoubtfulWordSpan(range: 1..<3, kind: .lowScore, evidence: 0)])
    }

    @Test func anEngineWithoutRealScoresIsNotAvailable() {
        let doubtful = DoubtfulWordsOutcome.locating(
            Transcription(text: "send the report"), in: "Send the report.")
        #expect(doubtful == .notAvailable)
    }

    /// The 5 s and 30 s fixtures' word counts; the bound is a debug-build regression ceiling, the release reading is in Docs/recogniser-evidence.md.
    @Test(arguments: [12, 80])
    func placingStaysCheap(words count: Int) {
        let text = (0..<count).map { $0.isMultiple(of: 7) ? "blorp" : "word" }.joined(separator: " ")
        let spoken = heard(text, doubted: ["blorp"])
        let written = text.capitalized + "."
        var samples: [Duration] = []
        for _ in 0..<200 {
            let start = ContinuousClock.now
            _ = DoubtfulWordsOutcome.locating(spoken, in: written)
            samples.append(ContinuousClock.now - start)
        }
        let p95 = samples.sorted()[189]
        print("doubtful-words placing, \(count) words: p95 \(p95)")
        #expect(p95 < .milliseconds(50))
    }
}
