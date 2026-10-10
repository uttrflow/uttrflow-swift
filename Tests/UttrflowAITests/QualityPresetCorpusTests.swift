import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("A small corpus cleaned under each quality preset")
struct QualityPresetCorpusTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let preset: QualityPreset.ID
        let spoken: String
        let written: String
        var testDescription: String { "\(preset): \(spoken)" }
    }

    static let corpus: [Case] = [
        Case(preset: .standard, spoken: "um we ship on friday", written: "We ship on Friday."),
        Case(preset: .verbatim, spoken: "um we ship on friday", written: "Um we ship on Friday."),
        Case(preset: .code, spoken: "um we ship on friday", written: "we ship on friday"),
        Case(
            preset: .standard, spoken: "we should we should leave at noon",
            written: "We should leave at noon."),
        Case(
            preset: .verbatim, spoken: "we should we should leave at noon",
            written: "We should we should leave at noon."),
        Case(preset: .standard, spoken: "the loop runs five times", written: "The loop runs five times."),
        Case(preset: .code, spoken: "the loop runs five times", written: "the loop runs 5 times"),
        Case(preset: .verbatim, spoken: "yes comma that works", written: "Yes, that works."),
    ]

    @Test("each preset writes the expected text for a plain-text field", arguments: corpus)
    func cleansUnderPreset(example: Case) {
        let preset = QualityPreset.preset(example.preset)
        let pipeline = CleaningPipeline.standard(
            for: preset.applied(to: .standard(for: .unknown)), situation: .unknown,
            steps: preset.applied(to: .default))
        let draft = Draft(romanising: Transcription(text: example.spoken))
        #expect(RuleBasedTransformer.audited(pipeline, over: draft).draft.text == example.written)
    }
}
