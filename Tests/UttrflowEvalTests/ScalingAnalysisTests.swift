import UttrflowCore
import Testing

@testable import UttrflowEval

@Suite("How cost grows with utterance length")
struct ScalingAnalysisTests {
    private func profile(
        _ length: ProfilePassage.Length,
        audio: Double,
        endToEnd: Double,
        transcription: Double? = nil
    ) -> UtteranceProfile {
        UtteranceProfile(
            length: length,
            audioSeconds: audio,
            endToEnd: DurationSummary(
                typical: .seconds(endToEnd), slowest: .seconds(endToEnd), samples: 3, failures: 0),
            stages: transcription.map {
                [
                    StageLatency(
                        stage: .transcription, typical: .seconds($0), slowest: .seconds($0),
                        samples: 3, failures: 0)
                ]
            } ?? [],
            unmeasuredStages: [.capture, .insertion]
        )
    }

    @Test("one step is not enough to see a bend")
    func oneStepIsUndetermined() {
        let analysis = ScalingAnalysis([profile(.short, audio: 3, endToEnd: 1)])
        #expect(analysis.steps.isEmpty)
        #expect(analysis.verdict == .undetermined)
    }

    @Test("an even cost per second of speech is linear")
    func linear() {
        let analysis = ScalingAnalysis([
            profile(.short, audio: 3, endToEnd: 1),
            profile(.medium, audio: 15, endToEnd: 2.2),
            profile(.long, audio: 60, endToEnd: 6.7),
        ])
        #expect(analysis.steps.count == 2)
        #expect(analysis.verdict == .linear)
    }

    /// The finding that invalidates signing a product off on fifteen-second tests.
    @Test("later seconds costing more is super-linear")
    func superLinear() {
        let analysis = ScalingAnalysis([
            profile(.short, audio: 3, endToEnd: 1),
            profile(.medium, audio: 15, endToEnd: 2.2),
            profile(.long, audio: 60, endToEnd: 20),
        ])
        #expect(analysis.verdict == .superLinear)
        #expect((analysis.steps.last?.marginalCost ?? 0) > (analysis.steps.first?.marginalCost ?? 0))
    }

    /// Fixed per-dictation overhead amortising away, which is what a healthy pipeline
    /// looks like.
    @Test("later seconds costing less is sub-linear")
    func subLinear() {
        let analysis = ScalingAnalysis([
            profile(.short, audio: 3, endToEnd: 1),
            profile(.medium, audio: 15, endToEnd: 2.2),
            profile(.long, audio: 60, endToEnd: 3.2),
        ])
        #expect(analysis.verdict == .subLinear)
    }

    @Test("the profiles need not arrive shortest first")
    func ordersByAudioLength() {
        let analysis = ScalingAnalysis([
            profile(.long, audio: 60, endToEnd: 6.7),
            profile(.short, audio: 3, endToEnd: 1),
            profile(.medium, audio: 15, endToEnd: 2.2),
        ])
        #expect(analysis.steps.map(\.from) == [.short, .medium])
        #expect(analysis.steps.map(\.to) == [.medium, .long])
    }

    /// A stage can bend while the journey around it looks straight, which is the whole
    /// reason the verdict is available per stage as well as overall.
    @Test("one stage is read on its own")
    func perStage() {
        let profiles = [
            profile(.short, audio: 3, endToEnd: 1, transcription: 0.5),
            profile(.medium, audio: 15, endToEnd: 2.2, transcription: 1.1),
            profile(.long, audio: 60, endToEnd: 6.7, transcription: 10),
        ]
        #expect(ScalingAnalysis(profiles).verdict == .linear)
        #expect(ScalingAnalysis(profiles, stage: .transcription).verdict == .superLinear)
    }

    /// A stage nothing timed must not become a point on the line at zero seconds.
    @Test("an untimed stage yields no steps rather than a flat one")
    func untimedStageIsNotZero() {
        let profiles = [
            profile(.short, audio: 3, endToEnd: 1),
            profile(.medium, audio: 15, endToEnd: 2.2),
        ]
        let analysis = ScalingAnalysis(profiles, stage: .insertion)
        #expect(analysis.steps.isEmpty)
        #expect(analysis.verdict == .undetermined)
    }

    @Test("two utterances of the same length cannot be compared")
    func zeroExtraAudioCostsNothing() {
        let analysis = ScalingAnalysis([
            profile(.short, audio: 3, endToEnd: 1),
            profile(.medium, audio: 3, endToEnd: 2),
            profile(.long, audio: 60, endToEnd: 6),
        ])
        #expect(analysis.steps.first?.marginalCost == 0)
        #expect(analysis.verdict == .undetermined)
    }
}

@Suite("One utterance length's costs")
struct UtteranceProfileTests {
    private let profile = UtteranceProfile(
        length: .medium,
        audioSeconds: 14,
        endToEnd: DurationSummary(
            typical: .seconds(3.5), slowest: .seconds(4), samples: 3, failures: 1),
        stages: [
            StageLatency(
                stage: .transcription, typical: .seconds(1.5), slowest: .seconds(1.6), samples: 3,
                failures: 0)
        ],
        unmeasuredStages: [.capture, .insertion]
    )

    @Test("cost per second of speech and the real-time factor are two views of one number")
    func perSecondFigures() {
        #expect(profile.costPerAudioSecond == 3.5 / 14)
        #expect(profile.realTimeFactor == 14 / 3.5)
    }

    @Test("a length with no audio does not divide by zero")
    func noAudio() {
        let empty = UtteranceProfile(
            length: .short, audioSeconds: 0,
            endToEnd: DurationSummary(
                typical: .zero, slowest: .zero, samples: 1, failures: 0),
            stages: [], unmeasuredStages: [])
        #expect(empty.costPerAudioSecond == 0)
        #expect(empty.realTimeFactor == 0)
    }

    @Test("seconds are readable per stage and end to end")
    func wallSeconds() {
        #expect(profile.wallSeconds(of: nil) == 3.5)
        #expect(profile.wallSeconds(of: .transcription) == 1.5)
        #expect(profile.wallSeconds(of: .insertion) == nil)
    }
}
