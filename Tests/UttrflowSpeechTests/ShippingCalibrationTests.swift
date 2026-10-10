// The shipping calibrations and the layers each was fitted under; a moved layer fails here until refitted.
import Testing
@testable import UttrflowAI
import UttrflowCore
@testable import UttrflowSpeech

struct ShippingCalibrationTests {
    typealias Layer = CalibrationRecord.Layer

    static let plan = SpeechFallbackPlan.shipping

    /// Each layer's revision as the code ships it now.
    static let live: [Layer: String] = [
        .recogniser: "\(SpeechModel.default.variant)@\(SpeechModel.default.weightsRevision)",
        .phraseBias: "\(SpeechEngineFactory.shippingPhraseBias)",
        .conditioningPrompt: [
            "\(VocabularyPrompt.maximumTokens)", "\(VocabularyPrompt.maximumWordTokens)",
            "\(VocabularyPrompt.maximumLeadTokens)", VocabularyPrompt.opening, VocabularyPrompt.closing,
        ].joined(separator: "|"),
        .fallbackPlan: "\(plan.temperatureCount), \(plan.logProbThreshold)",
        .certaintyThreshold: "\(DoubtPolicy.certaintyThreshold)",
        .overrideMargin: "\(DoubtPolicy.OverridePolicy.baseMargin)",
    ]

    /// The recognition layers as they were when the shipping calibrations were recorded.
    static let recordedUnder: [Layer: String] = [
        .recogniser: "openai_whisper-large-v3-v20240930_turbo_632MB"
            + "@0f63a7800b00dd0226abd051b906c246e1907482",
        .phraseBias: "0.0",
        .conditioningPrompt: "111|48|48| The words used here are|.",
    ]

    /// Every calibration the product ships, in fit order, with what it was fitted on and under.
    static func ledger(under recognition: [Layer: String]) -> [CalibrationRecord] {
        [
            CalibrationRecord(
                layer: .fallbackPlan, value: "5, -1.0",
                corpus: "8 English clips, 3 runs, clean and 10 dB noise; Docs/speech-engines.md",
                metric: "fallback rate, extra seconds, repeatability and WER", fittedUnder: recognition),
            CalibrationRecord(
                layer: .certaintyThreshold, value: "0.5",
                corpus: "none: chosen, not fitted; Docs/ai-correction-thresholds.md",
                metric: "the score above which a recogniser claims more right than wrong",
                fittedUnder: recognition.merging([.fallbackPlan: "5, -1.0"]) { $1 }),
            CalibrationRecord(
                layer: .overrideMargin, value: "2",
                corpus: "none: argued from counted signals; Docs/ai-correction-thresholds.md",
                metric: "no single coincidence swaps a word", fittedUnder: [.certaintyThreshold: "0.5"]),
        ]
    }

    @Test func everyShippingCalibrationWasFittedUnderTheLayersAsTheyShip() {
        #expect(CalibrationGraph.findings(Self.ledger(under: Self.recordedUnder), live: Self.live) == [])
    }

    @Test func everyCalibratedLayerHasOneRecord() {
        let layers = Self.ledger(under: Self.recordedUnder).map(\.layer)
        #expect(layers == Layer.allCases.filter { $0 >= .fallbackPlan })
    }

    @Test func movingThePhraseBiasFailsUntilTheDependentCalibrationsAreRecordedAgain() {
        var live = Self.live
        live[.phraseBias] = "1.5"
        #expect(
            CalibrationGraph.findings(Self.ledger(under: Self.recordedUnder), live: live) == [
                .upstreamMoved(.fallbackPlan, upstream: .phraseBias, recorded: "0.0", live: "1.5"),
                .upstreamMoved(.certaintyThreshold, upstream: .phraseBias, recorded: "0.0", live: "1.5"),
                .upstreamStale(.certaintyThreshold, upstream: .fallbackPlan),
                .upstreamStale(.overrideMargin, upstream: .certaintyThreshold),
            ])

        var refitted = Self.recordedUnder
        refitted[.phraseBias] = "1.5"
        #expect(CalibrationGraph.findings(Self.ledger(under: refitted), live: live) == [])
    }
}
