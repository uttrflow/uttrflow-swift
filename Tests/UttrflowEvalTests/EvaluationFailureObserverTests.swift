import Foundation
import Synchronization
import Testing
import UttrflowCore

@testable import UttrflowEval

@Suite("Evaluation failure observation preserves scores and excludes error payloads")
struct EvaluationFailureObserverTests {
    private let cases = [
        EvaluationCase(id: "a", category: .everyday, spoken: "hello", expected: "Hello."),
        EvaluationCase(id: "b", category: .everyday, spoken: "goodbye", expected: "Goodbye."),
    ]

    private struct OpaqueFailure: Error, CustomStringConvertible {
        let description = "Synthetic payload that must never become a diagnostic."
    }

    @Test("typed model errors and cancellation report only their closed category")
    func observesFailureCategories() async {
        let observed = Mutex<[(String, ModelFailureClass)]>([])
        let report = await EvaluationRunner(cases: cases).run(
            label: "failures",
            onFailure: { testCase, category in
                observed.withLock { $0.append((testCase.id, category)) }
            }
        ) { testCase in
            if testCase.id == "a" {
                throw TransformationError.transformFailed(kind: .foundationModels, failure: .timedOut)
            }
            throw CancellationError()
        }
        let failures = observed.withLock { $0 }
        #expect(failures.map(\.0) == ["a", "b"])
        #expect(failures.map(\.1) == [.timedOut, .cancelled])
        #expect(report.scores == cases.map { Scorer.score("", against: $0) })
        #expect(report.durations.count == 2)
        #expect(report.passRate == 0)
        #expect(report.declinedCount == 0)
    }

    @Test("opaque error text is discarded and the next case still succeeds")
    func ignoresUnknownPayloads() async {
        let observed = Mutex<[ModelFailureClass]>([])
        let report = await EvaluationRunner(cases: cases).run(
            label: "opaque", onFailure: { _, category in observed.withLock { $0.append(category) } }
        ) { testCase in
            if testCase.id == "a" { throw OpaqueFailure() }
            return .produced(testCase.expected)
        }
        #expect(observed.withLock { $0 } == [.other])
        #expect(report.scores[0] == Scorer.score("", against: cases[0]))
        #expect(report.scores[1].passed)
        #expect(report.passRate == 0.5)
    }

    @Test("empty successful answers and declined cases never report a thrown failure")
    func successfulEmptyAndDeclinedAreNotErrors() async {
        let observed = Mutex<[ModelFailureClass]>([])
        let report = await EvaluationRunner(cases: cases).run(
            label: "empty", onFailure: { _, category in observed.withLock { $0.append(category) } }
        ) { testCase in testCase.id == "a" ? .produced("") : .declined }
        #expect(observed.withLock { $0 }.isEmpty)
        #expect(report.scores[0] == Scorer.score("", against: cases[0]))
        #expect(report.declinedCount == 1)
        #expect(report.durations.count == 2)
    }

    @Test("every existing typed model category survives observation", arguments: ModelFailureClass.allCases)
    func preservesTypedCategories(category: ModelFailureClass) async {
        let observed = Mutex<[ModelFailureClass]>([])
        let report = await EvaluationRunner(cases: [cases[0]]).run(
            label: "typed", onFailure: { _, category in observed.withLock { $0.append(category) } }
        ) { _ in throw TransformationError.transformFailed(kind: .rules, failure: category) }
        #expect(observed.withLock { $0 } == [category])
        #expect(report.scores == [Scorer.score("", against: cases[0])])
    }

    @Test("other transformation cases discard reasons and retain cancellation")
    func transformationWithoutModelCategory() async {
        let samples: [(TransformationError, ModelFailureClass)] = [
            (.cancelled, .cancelled), (.noCapableTransformer, .other),
            (
                .outputRejected(reason: "Synthetic reason excluded from diagnostics.", kind: .emptyRewrite),
                .other
            ),
        ]
        for (error, expected) in samples {
            let observed = Mutex<[ModelFailureClass]>([])
            let report = await EvaluationRunner(cases: [cases[0]]).run(
                label: "transformation",
                onFailure: { _, category in observed.withLock { $0.append(category) } }
            ) { _ in throw error }
            #expect(observed.withLock { $0 } == [expected])
            #expect(report.scores == [Scorer.score("", against: cases[0])])
        }
    }

}
