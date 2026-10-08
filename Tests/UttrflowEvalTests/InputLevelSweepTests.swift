// Tests the gain and clipping variants a passage is replayed at.
import Testing
import UttrflowEval

@Suite("InputLevelSweep")
struct InputLevelSweepTests {
    private let clip: [Float] = (0..<1_000).map { Float($0 % 50 - 25) / 100 }

    @Test func theSweepRunsFromQuietToClipped() {
        #expect(
            InputLevel.sweep.map(\.description) == [
                "-40 dBFS", "-30 dBFS", "-20 dBFS", "-10 dBFS", "0 dBFS",
                "2x clipped", "4x clipped", "8x clipped",
            ])
    }

    @Test func aPeakLevelMovesThePeakWithoutClipping() {
        let quiet = InputLevel.peak(decibels: -20).applied(to: clip)
        #expect(abs(CueBleed.peakDecibels(of: quiet) + 20) < 1e-4)
        #expect(quiet.allSatisfy { abs($0) <= 0.1 + 1e-6 })
    }

    @Test func moreGainClipsAShareOfSamplesThatOnlyGrows() {
        let variants = [Float(2), 4, 8].map { InputLevel.clipped(gain: $0).applied(to: clip) }
        #expect(variants.allSatisfy { $0.allSatisfy { $0.magnitude <= 1 } })
        let fractions = variants.map(clippedFraction)
        #expect(fractions[0] > 0)
        #expect(fractions[0] < fractions[1])
        #expect(fractions[1] < fractions[2])
    }

    private func clippedFraction(_ samples: [Float]) -> Double {
        Double(samples.count { $0.magnitude >= 0.999 }) / Double(samples.count)
    }

    @Test func theSameClipGivesTheSameVariantEveryRun() {
        let level = InputLevel.clipped(gain: 4)
        #expect(level.applied(to: clip) == level.applied(to: clip))
    }

    @Test func silenceStaysSilentAtEveryLevel() {
        for level in InputLevel.sweep { #expect(level.applied(to: [0, 0]) == [0, 0]) }
    }
}
