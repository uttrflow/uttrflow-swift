import Foundation

/// What an engine did with one case.
public enum EvaluationOutcome: Sendable, Equatable {
    case produced(String)
    /// The engine reports it cannot handle this case, most often a language it does not know; not a failure.
    case declined
}

/// Runs the corpus through one transformer it knows nothing about, so engines compare honestly.
public struct EvaluationRunner: Sendable {
    private let cases: [EvaluationCase]

    public init(cases: [EvaluationCase] = EvaluationCorpus.all) {
        self.cases = cases
    }

    /// Scores every case under `label`; a throw from `transform` is a failed case, not an abandoned run.
    public func run(
        label: String,
        onCase: (@Sendable (EvaluationCase) -> Void)? = nil,
        transform: (EvaluationCase) async throws -> EvaluationOutcome
    ) async -> EvaluationReport {
        var scores: [CaseScore] = []
        var durations: [Duration] = []
        let clock = ContinuousClock()

        for testCase in cases {
            onCase?(testCase)
            let start = clock.now
            let outcome = (try? await transform(testCase)) ?? .produced("")
            durations.append(start.duration(to: clock.now))

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
}
