import FoundationModels
import Testing

@testable import UttrflowAI
@testable import UttrflowCore

/// Every error case the system model can throw lands in one closed class, judged by case alone.
@Suite("ModelFailureClassifier")
struct ModelFailureClassifierTests {
    /// A context whose text must never decide the class.
    private static let context = LanguageModelSession.GenerationError.Context(
        debugDescription: "guardrail context window rate limited")

    /// Each case of the system model's error type and the class it must arrive as.
    private static let table: [(LanguageModelSession.GenerationError, ModelFailureClass)] = [
        (.exceededContextWindowSize(context), .contextTooLarge),
        (.assetsUnavailable(context), .notReady),
        (.guardrailViolation(context), .guardrail),
        (.unsupportedGuide(context), .unsupportedSchema),
        (.unsupportedLanguageOrLocale(context), .unsupportedLanguage),
        (.decodingFailure(context), .decoding),
        (.rateLimited(context), .rateLimited),
        (.concurrentRequests(context), .rateLimited),
        (.refusal(.init(transcriptEntries: []), context), .refusedByModel),
    ]

    @Test("maps every generation error case to its class", arguments: table)
    func mapsGenerationErrors(error: LanguageModelSession.GenerationError, expected: ModelFailureClass) {
        #expect(ModelFailureClass.ofSystemModel(error) == expected)
    }

    @Test("maps a cancellation to cancelled")
    func mapsCancellation() {
        #expect(ModelFailureClass.ofSystemModel(CancellationError()) == .cancelled)
    }

    /// An error no model framework names.
    private struct Unnamed: Error {}

    @Test("maps an error it does not know to other")
    func mapsUnknown() {
        #expect(ModelFailureClass.ofSystemModel(Unnamed()) == .other)
    }

    @Test("gives every class a summary that is not empty and not repeated")
    func summariesAreDistinct() {
        let summaries = ModelFailureClass.allCases.map(\.summary)
        #expect(summaries.allSatisfy { !$0.isEmpty })
        #expect(Set(summaries).count == summaries.count)
    }
}
