import Testing

@testable import UttrflowAI
@testable import UttrflowCore

@Suite("What each stage of one dictation decided")
struct DictationExplanationTests {
    /// A transcript whose timed words spell its text, so its confidences are real.
    private let scored = TransformationRequest(
        transcription: Transcription(
            text: "we ship it",
            segments: [
                TranscriptionSegment(
                    text: "we ship it", start: .zero, end: .seconds(1),
                    words: [
                        TranscribedWord(text: "we", confidence: 0.98),
                        TranscribedWord(text: "ship", confidence: 0.41),
                        TranscribedWord(text: "it", confidence: 0.9),
                    ])
            ]))

    /// A record with one of every kind of fact the router and the passes keep.
    private let record = CleaningRecord(
        changes: [CleaningRecord.Change(step: .fillers, removed: ["um"])],
        switchedOff: [.stammers],
        refusals: [.init(engine: "localModel", reason: "it dropped ship", kind: .lostWord)],
        unavailableEngines: [.init(engine: "foundationModels", reason: .appleIntelligenceDisabled)],
        engineFailures: [.init(engine: "cloud", failureClass: .timedOut)])

    @Test("names every stage's input, output and reason in the order they ran")
    func everyStage() {
        let explanation = DictationExplanation(
            request: scored, spoken: "we ship it",
            doubtful: [DoubtfulSpan(heard: "ship", confidence: 0.41, candidates: ["chip", "shop"])],
            result: TransformationResult(text: "We chip it.\nDone", producedBy: .rules, cleaning: record))
        #expect(
            explanation.lines == [
                "heard      we ship it",
                "words      we 0.98, ship 0.41, it 0.90",
                "doubtful   \"ship\" at 0.41 → chip, shop",
                "for model  we ship it",
                "skipped    foundationModels: Apple Intelligence is switched off",
                "failed     cloud: timedOut",
                "refused    localModel: it dropped ship",
                "step       Filler words: removed 1: um",
                "off        Stammers",
                "tidied by  rules",
                "result     We chip it.⏎Done",
            ])
    }

    @Test("a transcript with no word scores says so rather than showing a stand-in score")
    func unscoredWords() {
        let explanation = DictationExplanation(
            request: TransformationRequest(transcription: Transcription(text: "we ship it")),
            spoken: "we ship it", doubtful: [],
            result: TransformationResult(text: "We ship it.", producedBy: .untidied))
        #expect(
            explanation.lines == [
                "heard      we ship it",
                "words      not scored: the recogniser gave no confidences that spell the text",
                "doubtful   none with another reading",
                "for model  we ship it",
                "steps      no record kept by untidied",
                "tidied by  untidied",
                "result     We ship it.",
            ])
    }

    @Test("tracing through the rules reports the words the passes gave the model and each step")
    func tracesTheRules() async throws {
        let explanation = try await DictationExplanation.tracing(
            TransformationRequest(transcription: Transcription(text: "um we ship fifteen builds")),
            through: TransformerRouter(engines: [RuleBasedTransformer()], preference: [.rules]))
        #expect(explanation.spoken == "we ship 15 builds")
        #expect(explanation.doubtful.isEmpty)
        #expect(explanation.result.producedBy == .rules)
        #expect(explanation.lines.contains("step       Filler words: removed 1: um"))
        #expect(explanation.lines.last == "result     \(explanation.result.text)")
    }

    @Test("prints the model's raw answer after the refusals, line breaks shown")
    func modelAnswer() {
        let explanation = DictationExplanation(
            request: scored, spoken: "we ship it", doubtful: [],
            result: TransformationResult(
                text: "We ship it.", producedBy: .localModel,
                cleaning: CleaningRecord(changes: [], modelAnswers: ["Here you go:\nwe ship it"])))
        #expect(explanation.lines.contains("model said Here you go:⏎we ship it"))
    }
}
