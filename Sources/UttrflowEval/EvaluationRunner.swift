// Runs the clean-up corpus through one transformer.
import Foundation
public import UttrflowCore

/// What an engine did with one case.
public enum EvaluationOutcome: Sendable, Equatable {
    case produced(String)
    /// The engine reports it cannot handle this case, most often a language it does not know; not a failure.
    case declined
}

/// Runs the corpus through one transformer it knows nothing about, so engines compare honestly.
public struct EvaluationRunner: Sendable {
    private let cases: [EvaluationCase]

    public init(cases: [EvaluationCase] = EvaluationCorpus.all, shape: InputShape = .bare) {
        self.cases = cases.map { $0.shaped(shape) }
    }

    /// Scores every case under `label`; a throw from `transform` is a failed case, not an abandoned run.
    public func run(
        label: String,
        onCase: (@Sendable (EvaluationCase) -> Void)? = nil,
        onFailure: (@Sendable (EvaluationCase, ModelFailureClass) -> Void)? = nil,
        transform: (EvaluationCase) async throws -> EvaluationOutcome
    ) async -> EvaluationReport {
        var scores: [CaseScore] = []
        var durations: [Duration] = []
        let clock = ContinuousClock()

        for testCase in cases {
            onCase?(testCase)
            let start = clock.now
            let (outcome, failure) = await Self.evaluate(testCase, using: transform)
            durations.append(start.duration(to: clock.now))
            if let failure { onFailure?(testCase, failure) }

            switch outcome {
            case .produced(let text):
                scores.append(Scorer.score(text, against: testCase))
            case .declined:
                scores.append(
                    CaseScore(
                        caseID: testCase.id, similarity: 0, keptEverythingRequired: true,
                        lost: [], isExact: false, declined: true
                    )
                )
            }
        }

        return EvaluationReport(
            label: label, scores: scores, durations: durations,
            peakMemoryBytes: MemoryFootprint.current()
        )
    }

    private static func evaluate(
        _ testCase: EvaluationCase,
        using transform: (EvaluationCase) async throws -> EvaluationOutcome
    ) async -> (EvaluationOutcome, ModelFailureClass?) {
        do {
            return (try await transform(testCase), nil)
        } catch {
            let category: ModelFailureClass
            if let failure = error as? TransformationError {
                category =
                    switch failure {
                    case .transformFailed(_, let category): category
                    case .cancelled: .cancelled
                    case .noCapableTransformer, .outputRejected: .other
                    }
            } else {
                category = ModelFailureClass.of(error)
            }
            return (.produced(""), category)
        }
    }
}
