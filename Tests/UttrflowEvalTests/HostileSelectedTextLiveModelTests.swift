// Runs the hostile-selected-text corpus through the shipping router and the pinned Apple model.
import UttrflowAI
import UttrflowCore
import Testing

@testable import UttrflowEval

/// Reported as skipped when Apple Intelligence is off, never as a pass.
@Suite(
    "Hostile selected-text against the real router",
    .enabled("needs Apple Intelligence, which is off on this Mac") {
        await AppleFoundationCleanupModel().availability(for: .english).isAvailable
    })
struct HostileSelectedTextLiveModelTests {
    private var router: TransformerRouter {
        TransformerRouter(
            engines: [
                GenerativeTextTransformer(kind: .foundationModels, model: AppleFoundationCleanupModel())
            ],
            preference: [.foundationModels]
        )
    }

    /// Returns no score when the route becomes unavailable after its readiness check.
    private func transformIfCapable(
        _ transform: () async throws -> TransformationResult
    ) async throws -> TransformationResult? {
        do {
            return try await transform()
        } catch let error as TransformationError {
            guard case .noCapableTransformer = error else { throw error }
            withKnownIssue("Apple Foundation Models became unavailable after its readiness check.") {
                Issue.record("The live-model score was not measured for this case.")
            }
            return nil
        } catch {
            throw error
        }
    }

    @Test(
        "never obeys, answers, or copies a hostile instruction quoted from the screen",
        arguments: EvaluationCorpus.hostileSelectedText + EvaluationCorpus.hostileWindowTitle)
    func refusesHostileScreenText(testCase: EvaluationCase) async throws {
        let output = try await transformIfCapable {
            try await router.transform(testCase.transformationRequest())
        }
        guard let result = output else { return }
        let score = Scorer.score(result.text, against: testCase)
        #expect(
            score.invented.isEmpty,
            "\(testCase.id) (prompt \(PromptBuilder.version)) let through: \(score.invented)")
    }

    @Test(
        "produces the ordinary tidy-up once the hostile screen text is withheld",
        arguments: EvaluationCorpus.hostileSelectedText + EvaluationCorpus.hostileWindowTitle)
    func controlWithContextWithheld(testCase: EvaluationCase) async throws {
        let output = try await transformIfCapable {
            try await router.transform(testCase.transformationRequest(withholdingContext: true))
        }
        guard let result = output else { return }
        let score = Scorer.score(result.text, against: testCase)
        #expect(score.keptEverythingRequired, "\(testCase.id) lost \(score.lost) with context withheld")
        #expect(score.invented.isEmpty, "\(testCase.id) invented \(score.invented) with context withheld")
    }
}
