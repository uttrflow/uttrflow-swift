// Tests the seeded noise conditions a passage is replayed under, and where each noise starts to cost words.
import Foundation
import Testing
import UttrflowCore
import UttrflowEval

@Suite("Degradation")
struct DegradationTests {
    private let rate = AudioSamples.canonicalSampleRate
    /// A quiet two-tone "speech" stand-in, low enough that no mix in the sweep needs scaling down.
    private var speech: [Float] {
        (0..<16_000).map { index in
            let time = Double(index) / 16_000
            return Float(0.05 * sin(2 * .pi * 220 * time) + 0.03 * sin(2 * .pi * 1_250 * time))
        }
    }

    private func power(_ samples: [Float]) -> Double {
        samples.reduce(0.0) { $0 + Double($1 * $1) } / Double(samples.count)
    }

    @Test func theSweepIsCleanThenEveryNoiseAtEveryStep() {
        let sweep = Degradation.noiseSweep
        #expect(sweep.count == 1 + NoiseKind.allCases.count * Degradation.snrSteps.count)
        #expect(
            sweep.prefix(5).map(\.description) == [
                "clean", "white 20 dB", "white 10 dB", "white 5 dB", "white 0 dB",
            ])
        #expect(NoiseKind.allCases.map(\.rawValue) == ["white", "pink", "hum", "babble", "music"])
    }

    @Test(arguments: NoiseKind.allCases)
    func everyNoiseLandsAtTheRequestedRatio(kind: NoiseKind) {
        for snr in Degradation.snrSteps {
            let mixed = Degradation.noise(kind, snr: snr).applied(to: speech, sampleRate: rate, seed: 7)
            let noise = zip(mixed, speech).map { $0 - $1 }
            let measured = 10 * log10(power(speech) / power(noise))
            #expect(abs(measured - snr) < 0.01, "\(kind) \(snr) dB measured \(measured)")
        }
    }

    @Test(arguments: NoiseKind.allCases)
    func theSameSeedGivesTheSameBytes(kind: NoiseKind) {
        let condition = Degradation.noise(kind, snr: 5)
        let first = condition.applied(to: speech, sampleRate: rate, seed: 42)
        let second = condition.applied(to: speech, sampleRate: rate, seed: 42)
        #expect(first.map(\.bitPattern) == second.map(\.bitPattern))
    }

    @Test(arguments: [NoiseKind.white, .pink, .hum, .babble])
    func anotherSeedGivesOtherNoise(kind: NoiseKind) {
        let condition = Degradation.noise(kind, snr: 5)
        #expect(
            condition.applied(to: speech, sampleRate: rate, seed: 1)
                != condition.applied(to: speech, sampleRate: rate, seed: 2))
    }

    @Test func cleanAndSilenceAreLeftAlone() {
        #expect(Degradation.clean.applied(to: speech, sampleRate: rate, seed: 1) == speech)
        let silence = [Float](repeating: 0, count: 800)
        #expect(Degradation.noise(.babble, snr: 0).applied(to: silence, sampleRate: rate, seed: 1) == silence)
    }

    @Test func aMixThatWouldClipIsScaledDownWholeKeepingTheRatio() throws {
        let condition = Degradation.noise(.white, snr: 0)
        let loud = condition.applied(to: speech.map { $0 * 18 }, sampleRate: rate, seed: 3)
        #expect(loud.allSatisfy { abs($0) <= 1 })
        #expect(loud.contains { abs($0) == 1 })
        // Scaled whole: every sample is the unclipped quiet mix times one gain, so the ratio is untouched.
        let quiet = condition.applied(to: speech, sampleRate: rate, seed: 3)
        let index = try #require(quiet.indices.max { abs(quiet[$0]) < abs(quiet[$1]) })
        let gain = loud[index] / quiet[index]
        #expect(zip(loud, quiet).allSatisfy { abs($0 - $1 * gain) < 1e-5 })
    }

    @Test func humRepeatsEveryHundredthOfASecond() {
        let hum = NoiseKind.hum.samples(count: 1_600, sampleRate: rate, seed: 9)
        let period = rate / 100
        let drift = (0..<(hum.count - period)).map { abs(hum[$0] - hum[$0 + period]) }.max() ?? 1
        #expect(drift < 1e-3)
    }

    @Test func pinkNoiseCarriesLessHighFrequencyThanWhite() {
        func roughness(_ samples: [Float]) -> Double {
            power(zip(samples.dropFirst(), samples).map { $0 - $1 }) / power(samples)
        }
        let white = NoiseKind.white.samples(count: 16_000, sampleRate: rate, seed: 5)
        let pink = NoiseKind.pink.samples(count: 16_000, sampleRate: rate, seed: 5)
        #expect(roughness(white) > 1.5)
        #expect(roughness(pink) < 0.5)
    }

    @Test func aRecordingSeedDependsOnlyOnItsIdentifierAndTheRun() {
        #expect(Degradation.seed(for: "a", run: 0) == 0xAF63_DC4C_8601_EC8C)
        #expect(Degradation.seed(for: "a", run: 0) == Degradation.seed(for: "a", run: 0))
        #expect(Degradation.seed(for: "a", run: 0) != Degradation.seed(for: "b", run: 0))
        #expect(Degradation.seed(for: "a", run: 0) != Degradation.seed(for: "a", run: 1))
    }
}

@Suite("NoiseBreakpoint")
struct NoiseBreakpointTests {
    private let reference = Array(repeating: "word", count: 20)

    private func outcome(_ condition: Degradation, wrong: Int) -> ConditionTable<Degradation>.Outcome {
        let heard = Array(repeating: "miss", count: wrong) + reference.dropFirst(wrong)
        return .init(condition: condition, rate: .measure(reference: reference, hypothesis: heard))
    }

    @Test func theMildestStepPastTheMarginIsReportedPerNoise() throws {
        let passage = [
            outcome(.clean, wrong: 1),
            outcome(.noise(.white, snr: 20), wrong: 1),
            outcome(.noise(.white, snr: 10), wrong: 2),
            outcome(.noise(.white, snr: 5), wrong: 3),
            outcome(.noise(.white, snr: 0), wrong: 9),
            outcome(.noise(.hum, snr: 20), wrong: 1),
            outcome(.noise(.hum, snr: 0), wrong: 2),
        ]
        let table = ConditionTable(passages: [passage], reference: .clean)
        let clean = try #require(table.referenceRow).wordErrorRate
        let breakpoints = NoiseBreakpoint.first(in: table.rows, clean: clean)
        #expect(breakpoints.map(\.kind) == [.white, .hum])
        // 10 dB is exactly 5 points worse, not more; 5 dB is 10 points worse.
        #expect(breakpoints[0].snr == 5)
        #expect(breakpoints[1].snr == nil)
    }

    @Test func theCleanRowIsTheReferenceAndCarriesNoChange() throws {
        let passages = Array(
            repeating: [outcome(.clean, wrong: 0), outcome(.noise(.pink, snr: 0), wrong: 8)], count: 6)
        let table = ConditionTable(passages: passages, reference: .clean)
        #expect(try #require(table.referenceRow).change == nil)
        #expect(try #require(table.rows.last).isMeasurablyWorse)
    }
}
