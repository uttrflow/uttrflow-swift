// Tests the deterministic tempo and pitch variants and the cut counts taken at each pace.
import Foundation
import Testing
import UttrflowCore
@testable import UttrflowEval

@Suite("Speech variants")
struct SpeechVariantTests {
    private let rate = AudioSamples.canonicalSampleRate

    private func tone(_ hertz: Double, seconds: Double) -> [Float] {
        (0..<Int(seconds * Double(rate))).map {
            Float(0.3 * sin(2 * .pi * hertz * Double($0) / Double(rate)))
        }
    }

    /// Frequency from rising zero crossings over the middle half, away from the overlap-add edges.
    private func frequency(_ samples: [Float]) -> Double {
        let span = samples.count / 4..<(3 * samples.count / 4)
        let crossings = zip(samples[span], samples[span].dropFirst()).filter { $0 <= 0 && $1 > 0 }.count
        return Double(crossings) / (Double(span.count) / Double(rate))
    }

    @Test(arguments: SpeechVariant.rateFactors)
    func stretchingScalesTheLengthAndKeepsThePitch(factor: Double) {
        let source = tone(220, seconds: 1)
        let result = TimeStretch.stretched(source, sampleRate: rate, rate: factor)
        #expect(result.count == Int((Double(source.count) / factor).rounded()))
        #expect(abs(frequency(result) - 220) < 220 * 0.03, "\(factor)x gave \(frequency(result)) Hz")
    }

    @Test(arguments: SpeechVariant.pitchSemitones)
    func shiftingMovesThePitchAndKeepsTheLength(semitones: Double) {
        let source = tone(220, seconds: 1)
        let result = PitchShift.shifted(source, sampleRate: rate, semitones: semitones)
        let expected = 220 * pow(2, semitones / 12)
        #expect(result.count == source.count)
        #expect(
            abs(frequency(result) - expected) < expected * 0.03, "\(semitones) st gave \(frequency(result))")
    }

    @Test func theSweepIsTheOriginalThenSixRatesAndFivePitches() {
        #expect(
            SpeechVariant.sweep.map(\.description) == [
                "1.0x", "0.7x", "0.85x", "1.3x", "1.6x", "1.9x", "-4 st", "-2 st", "+2 st", "+4 st", "+6 st",
            ])
    }

    @Test func aVariantIsTheSameEveryTime() {
        let source = tone(300, seconds: 0.5)
        for variant in SpeechVariant.sweep {
            #expect(
                variant.applied(to: source, sampleRate: rate) == variant.applied(to: source, sampleRate: rate)
            )
        }
        #expect(SpeechVariant.original.applied(to: source, sampleRate: rate) == source)
    }

    @Test func aClipShorterThanOneWindowStillComesBackAtTheNewLength() {
        let source = tone(220, seconds: 0.03)
        let result = TimeStretch.stretched(source, sampleRate: rate, rate: 1.5)
        #expect(result.count == Int((Double(source.count) / 1.5).rounded()))
        #expect(TimeStretch.stretched([], sampleRate: rate, rate: 1.5).isEmpty)
    }

    /// Two bursts of tone with a pause between, so the cutter has one pause to find.
    private func burstsWithPause(pause: Double) -> [Float] {
        let burst = tone(200, seconds: 3)
        return burst + [Float](repeating: 0, count: Int(pause * Double(rate))) + burst
    }

    @Test func aLongPauseCutsOnceBetweenTheBursts() {
        let structure = PaceStructure(samples: burstsWithPause(pause: 1.2), sampleRate: rate)
        #expect(structure.pieces == 2)
        #expect(structure.cuts.count == 1)
        #expect(structure.speechSeconds > 5.5)
    }

    @Test func fastingTheSpeechShortensThePauseBelowTheCut() {
        let slow = PaceStructure(samples: burstsWithPause(pause: 1.2), sampleRate: rate)
        let fast = PaceStructure(
            samples: SpeechVariant.rate(1.9).applied(
                to: burstsWithPause(pause: 1.2), sampleRate: rate), sampleRate: rate)
        #expect(slow.pieces == 2)
        #expect(fast.pieces == 1)
    }

    @Test func aCutIsInsideAWordOnlyWhenItFallsStrictlyBetweenItsEnds() {
        let structure = PaceStructure(samples: burstsWithPause(pause: 1.2), sampleRate: rate)
        let cut = structure.cuts[0]
        #expect(structure.cutsInsideWords([(cut - 0.2)...(cut + 0.2)]) == 1)
        #expect(structure.cutsInsideWords([(cut - 0.5)...cut]) == 0)
        #expect(structure.cutsInsideWords([]) == 0)
    }

    @Test func aContinuousToneIsCutAtItsMaximumLength() {
        let structure = PaceStructure(samples: tone(200, seconds: 40), sampleRate: rate)
        #expect(structure.pieces >= 2)
        #expect(structure.cuts.count == structure.pieces - 1)
    }
}
