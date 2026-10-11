// Tests the room and channel conditions a passage is replayed under: reverberation, band-limiting, mu-law coding.
import Foundation
import Testing
import UttrflowCore
import UttrflowEval

@Suite("Channel degradation")
struct ChannelDegradationTests {
    private let rate = AudioSamples.canonicalSampleRate

    private func tone(_ hertz: Double, count: Int = 16_000, amplitude: Double = 0.4) -> [Float] {
        (0..<count).map { Float(amplitude * sin(2 * .pi * hertz * Double($0) / Double(rate))) }
    }

    private func power(_ samples: some Sequence<Float>) -> Double {
        let values = Array(samples)
        return values.reduce(0.0) { $0 + Double($1 * $1) } / Double(max(values.count, 1))
    }

    @Test func theChannelSweepIsEveryRoomThenBandThenTelephone() {
        #expect(
            Degradation.channelSweep.map(\.description) == [
                "reverb 0.3 s", "reverb 0.6 s", "reverb 1.0 s", "band 8 kHz", "band 4 kHz", "mu-law 8 kHz",
            ])
    }

    @Test(arguments: Degradation.channelSweep)
    func theSameSeedGivesTheSameBytes(condition: Degradation) {
        let speech = tone(300) + tone(1_700)
        let first = condition.applied(to: speech, sampleRate: rate, seed: 11)
        let second = condition.applied(to: speech, sampleRate: rate, seed: 11)
        #expect(first.count == speech.count)
        #expect(first.map(\.bitPattern) == second.map(\.bitPattern))
    }

    @Test(arguments: Degradation.channelSweep)
    func silenceStaysSilent(condition: Degradation) {
        let silence = [Float](repeating: 0, count: 800)
        #expect(condition.applied(to: silence, sampleRate: rate, seed: 1) == silence)
    }

    @Test func aReverberantRoomKeepsTheLevelAndRingsForAsLongAsItsReverberationTime() {
        var click = [Float](repeating: 0, count: 32_000)
        click[0] = 0.5
        for rt60 in [0.3, 1.0] {
            let wet = Degradation.reverb(rt60: rt60).applied(to: click, sampleRate: rate, seed: 4)
            #expect(abs(power(wet) / power(click) - 1) < 0.01)
            let early = power(wet[1_600..<3_200])
            let late = power(wet[12_800..<14_400])
            if rt60 > 0.5 {
                #expect(early > 0 && late > 0 && late < early)
            } else {
                // Past the reverberation time the response is exactly zero.
                #expect(late / early < 1e-9)
            }
            #expect(wet[1_600..<3_200].contains { $0 != 0 })
        }
    }

    @Test func anotherSeedGivesAnotherRoom() {
        let speech = tone(300)
        let condition = Degradation.reverb(rt60: 0.6)
        #expect(
            condition.applied(to: speech, sampleRate: rate, seed: 1)
                != condition.applied(to: speech, sampleRate: rate, seed: 2))
    }

    @Test func bandLimitingPassesLowToneAndStopsHighOne() {
        let limit = Degradation.bandLimited(cutoff: 4_000)
        let low = limit.applied(to: tone(1_000), sampleRate: rate, seed: 0)
        let high = limit.applied(to: tone(6_000), sampleRate: rate, seed: 0)
        #expect(power(low[200..<15_800]) / power(tone(1_000)) > 0.95)
        #expect(power(high[200..<15_800]) / power(tone(6_000)) < 0.01)
    }

    @Test func aCutoffAtOrPastNyquistLeavesTheClipAlone() {
        let speech = tone(1_000)
        #expect(
            Degradation.bandLimited(cutoff: 8_000).applied(to: speech, sampleRate: rate, seed: 0) == speech)
    }

    @Test func muLawKeepsTheTelephoneBandAndDropsWhatIsAbove() {
        let coded = Degradation.muLaw.applied(to: tone(440), sampleRate: rate, seed: 0)
        let error = zip(coded, tone(440)).map { $0 - $1 }
        #expect(power(error[200..<15_800]) / power(tone(440)) < 0.01)
        let high = Degradation.muLaw.applied(to: tone(6_000), sampleRate: rate, seed: 0)
        #expect(power(high[200..<15_800]) / power(tone(6_000)) < 0.01)
    }

    @Test func muLawQuantisesToEightBits() {
        let coded = Degradation.muLaw.applied(to: tone(300), sampleRate: 8_000, seed: 0)
        #expect(Set(coded.map(\.bitPattern)).count <= 256)
    }
}
