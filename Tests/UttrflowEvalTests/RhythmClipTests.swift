import Testing
import UttrflowCore
import UttrflowEval

struct RhythmClipTests {
    private let rate = AudioSamples.canonicalSampleRate
    private let testCase = EvaluationCorpus.longForm[0]

    private func tone(_ milliseconds: Int) -> [Float] {
        let quiet = [Float](repeating: 0, count: 100 * rate / 1000)
        let voiced = (0..<(milliseconds * rate / 1000)).map {
            ($0 / 8).isMultiple(of: 2) ? Float(0.3) : Float(-0.3)
        }
        return quiet + voiced + quiet
    }

    private func profile(hesitation: Int) -> SpeakerProfile {
        SpeakerProfile(voice: "V", rate: nil, name: "p", hesitation: hesitation, breakLength: 900)
    }

    @Test func aProfileWithoutHesitationBreaksTheCaseOnlyWhereItPauses() {
        let parts = RhythmClip.parts(of: testCase, for: profile(hesitation: 0))
        #expect(parts.map(\.isBreak) == [true, true, true, false])
        #expect(parts.map(\.silenceMilliseconds) == [900, 900, 900, 0])
        let words = parts.flatMap { $0.text.split(separator: " ") }
        #expect(words.count == WordTokens.words(testCase.spoken, .display).count)
    }

    @Test func aHesitatingProfileAddsShorterSilencesInsideSentences() {
        let parts = RhythmClip.parts(of: testCase, for: profile(hesitation: 250))
        let hesitations = parts.filter { $0.silenceMilliseconds == 250 }
        #expect(!hesitations.isEmpty)
        #expect(hesitations.allSatisfy { !$0.isBreak })
        #expect(parts.filter(\.isBreak).count == 3)
    }

    @Test func theDefaultPacesRunFromFastToSlowWithLongerBreaksWhenSlower() {
        let paces = SpeakerProfile.paces(voice: "V")
        #expect(paces.map(\.name) == ["fast", "ordinary", "slow"])
        #expect(paces.map(\.breakMilliseconds) == paces.map(\.breakMilliseconds).sorted())
        #expect(paces[0].hesitationMilliseconds == 0)
    }

    @Test func gapsReadBackFromTheClipMatchTheSilencesBuiltAndMarkBreaks() throws {
        let parts = RhythmClip.parts(of: testCase, for: profile(hesitation: 250))
        let speech = parts.map { _ in tone(500) }
        let clip = try #require(RhythmClip.joined(parts, speech: speech, roomDecibels: -60))
        let gaps = clip.observations()
        #expect(gaps.count == parts.count - 1)
        for (gap, part) in zip(gaps, parts) {
            #expect(gap.isBreak == part.isBreak)
            #expect(abs(gap.milliseconds - Double(part.silenceMilliseconds)) < 120)
        }
    }

    @Test func aPartWithNoSpeechBuildsNoClip() {
        let parts = RhythmClip.parts(of: testCase, for: profile(hesitation: 0))
        let silent = [Float](repeating: 0, count: rate)
        #expect(RhythmClip.joined(parts, speech: parts.map { _ in silent }, roomDecibels: -60) == nil)
    }
}
