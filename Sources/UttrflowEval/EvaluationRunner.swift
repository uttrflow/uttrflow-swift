import Foundation

/// What an engine did with one case.
public enum EvaluationOutcome: Sendable, Equatable {
    case produced(String)
    /// The engine reported it could not handle this case — a language it does not
    /// know, most often. Not a failure.
    case declined
}

/// Runs the corpus through one transformer and measures what happened.
///
/// Knows nothing about which transformer it is running, so the same measurement
/// applies to Apple's model, a local one, and the deterministic floor — which is the
/// only way their numbers can be compared honestly.
public struct EvaluationRunner: Sendable {
    private let cases: [EvaluationCase]

    public init(cases: [EvaluationCase] = EvaluationCorpus.all) {
        self.cases = cases
    }

    /// - Parameters:
    ///   - label: How this run is named in the report.
    ///   - onCase: Called before each case, for progress.
    ///   - transform: Cleans one utterance, or reports that the engine cannot handle
    ///     it. Throwing is recorded as a failed case rather than abandoning the run —
    ///     a model that breaks on a third of the corpus should score badly, not go
    ///     unmeasured.
    /// - Returns: Scores, timings and peak memory for the whole corpus.
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
