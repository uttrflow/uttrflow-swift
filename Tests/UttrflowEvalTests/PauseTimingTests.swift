import Testing
import UttrflowCore
import UttrflowEval

struct PauseTimingTests {
    private let rate = AudioSamples.canonicalSampleRate

    private func tone(_ milliseconds: Int, padding: Int = 100) -> [Float] {
        let quiet = [Float](repeating: 0, count: padding * rate / 1000)
        let voiced = (0..<(milliseconds * rate / 1000)).map {
            ($0 / 8).isMultiple(of: 2) ? Float(0.3) : Float(-0.3)
        }
        return quiet + voiced + quiet
    }

    private func word(_ start: Double, _ end: Double) -> TranscribedWord {
        TranscribedWord(text: "w", confidence: 1, start: .seconds(start), end: .seconds(end))
    }

    private func trial(_ truth: Int, _ gap: Double?) -> PauseTiming.Trial {
        PauseTiming.Trial(kind: "k", truth: truth, wordGap: gap, audioGap: nil)
    }

    @Test func aJoinedClipHoldsTheTwoPhrasesTrimmedToTheirSpeechAroundTheExactPause() throws {
        let clip = try #require(
            PauseTiming.joined(tone(400), tone(300), gapMilliseconds: 300, roomDecibels: -90))
        #expect(clip.firstEnd == 400 * rate / 1000)
        #expect(clip.secondStart - clip.firstEnd == 300 * rate / 1000)
        #expect(clip.samples.count == (400 + 300 + 300) * rate / 1000)
    }

    @Test func aPhraseWithoutSpeechCannotBeJoined() {
        let silent = [Float](repeating: 0, count: rate)
        #expect(PauseTiming.joined(silent, tone(300), gapMilliseconds: 150, roomDecibels: -60) == nil)
        #expect(PauseTiming.joined(tone(300), silent, gapMilliseconds: 150, roomDecibels: -60) == nil)
    }

    @Test func voiceActivityReadsTheBuiltPauseBackToItsFrameResolution() throws {
        let clip = try #require(
            PauseTiming.joined(tone(500), tone(500), gapMilliseconds: 600, roomDecibels: -70))
        let gap = try #require(PauseTiming.voiceActivityGapMilliseconds(in: clip))
        #expect(abs(gap - 600) <= 40)
    }

    @Test func aWordGapIsTheNextStartLessThisEndAndNilWhenUntimedOrOutOfRange() {
        let words = [word(0, 0.4), word(0.7, 1), TranscribedWord(text: "x", confidence: 1)]
        #expect(PauseTiming.wordGapMilliseconds(after: 0, in: words).map { Int($0.rounded()) } == 300)
        #expect(PauseTiming.wordGapMilliseconds(after: 1, in: words) == nil)
        #expect(PauseTiming.wordGapMilliseconds(after: 2, in: words) == nil)
        #expect(PauseTiming.wordGapMilliseconds(after: -1, in: words) == nil)
    }

    @Test func theMedianIsTheMiddleValueOrTheMeanOfTheMiddleTwo() {
        #expect(PauseTiming.median([]) == 0)
        #expect(PauseTiming.median([3, 1, 2]) == 2)
        #expect(PauseTiming.median([4, 1, 2, 3]) == 2.5)
    }

    @Test func theTrustedMinimumIsTheShortestLengthFromWhichEveryLongerOneIsShownAccurately() {
        let trials = [
            trial(150, 0), trial(150, 40), trial(300, 280), trial(300, 310), trial(600, 590), trial(600, 610),
        ]
        #expect(PauseTiming.trustedMinimum(trials, tolerance: 50, shown: 150, reliability: 0.9) == 300)
        #expect(
            PauseTiming.trustedMinimum([trial(300, 0)], tolerance: 50, shown: 150, reliability: 0.9) == nil)
        #expect(
            PauseTiming.trustedMinimum([trial(300, nil)], tolerance: 50, shown: 150, reliability: 0.9) == nil)
    }

    @Test func theTableCountsRealPausesMissingAndShortOnesInvented() {
        let trials = [
            PauseTiming.Trial(kind: "a", truth: 0, wordGap: 400, audioGap: 0),
            PauseTiming.Trial(kind: "a", truth: 0, wordGap: 10, audioGap: 0),
            PauseTiming.Trial(kind: "a", truth: 600, wordGap: 100, audioGap: 600),
            PauseTiming.Trial(kind: "a", truth: 600, wordGap: 620, audioGap: 620),
        ]
        let table = PauseTiming.markdown(trials, skipped: 3)
        #expect(table.contains("| 0 ms | 2 | 2 | +205 | 205 | +0 | n/a | 50% |"))
        #expect(table.contains("| 600 ms | 2 | 2 | -240 | 260 | +10 | 50% | n/a |"))
        #expect(table.contains("skipped because the recogniser wrote a different number of words: 3"))
    }
}
