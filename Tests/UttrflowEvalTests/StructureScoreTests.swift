import Testing
import UttrflowAI
import UttrflowCore
import UttrflowTestSupport

@testable import UttrflowEval

/// Layout scored by break and list-item position, per destination, against the rates last recorded.
@Suite("Structure score")
struct StructureScoreTests {
    /// The rules engine's rates per destination, as last recorded in `Golden/structure-score.golden`.
    static let golden = GoldenFile(suite: "structure-score")

    /// Every corpus case whose reference has more than one line, which are the cases with a layout to score.
    static let laidOutCases = EvaluationCorpus.all.filter { $0.expected.contains("\n") }

    private static func rulesReport(rewriting: (String) -> String = { $0 }) async throws -> StructureReport {
        var scores: [StructureScore] = []
        for testCase in laidOutCases {
            let result = try await RuleBasedTransformer().transform(testCase.transformationRequest())
            scores.append(StructureScore(output: rewriting(result.text), for: testCase))
        }
        return StructureReport(scores: scores)
    }

    private func reference(_ expected: String) -> EvaluationCase {
        EvaluationCase(
            id: "case", category: .everyday, spoken: "spoken", expected: expected, destination: .document)
    }

    @Test("counts a right break, a missed break and a break inside a sentence apart")
    func scoresOneCase() {
        let testCase = reference("The trip is booked.\n\nThe hotel is near the station.\nWe leave at nine.")
        let score = StructureScore(
            output: "The trip is booked.\n\nThe hotel is near\nthe station. We leave at nine.", for: testCase)
        #expect(score.referenceBreaks == 2)
        #expect(score.outputBreaks == 2)
        #expect(score.correctBreaks == 1)
        #expect(score.breaksInsideSentence == 1)
        let rates = StructureRates([score])
        #expect(rates.precision == 0.5)
        #expect(rates.recall == 0.5)
        #expect(rates.overSegmentation == 0)
    }

    @Test("reads a paragraph break where a line break belongs as wrong, and aligns past a wrong word")
    func kindAndAlignment() {
        let testCase = reference("Dear team\nThe office is closed on Friday.")
        #expect(
            StructureScore(output: "Dear team\n\nThe office is closed on Friday.", for: testCase)
                .correctBreaks == 0)
        #expect(
            StructureScore(output: "Dear Tim\nThe office is shut on Friday.", for: testCase).correctBreaks
                == 1)
    }

    @Test("scores list items by the word they open, whatever the marker")
    func listItems() {
        let testCase = reference("1. Milk\n2. Eggs\n3. Bread")
        let bulleted = StructureScore(output: "- Milk\n- Eggs\n- Bread", for: testCase)
        #expect(bulleted.correctListItems == 3)
        #expect(bulleted.correctBreaks == 2)
        #expect(bulleted.breaksInsideSentence == 0)
        let joined = StructureScore(output: "1. Milk, eggs\n2. Bread", for: testCase)
        #expect(StructureRates([joined]).listItemAccuracy == 2.0 / 3.0)
        #expect(StructureRates([joined]).overSegmentation < 0)
    }

    @Test("leaves precision, recall and list accuracy unset where there is nothing to count")
    func emptyRatesAreUnset() {
        let rates = StructureRates([])
        #expect(rates.precision == nil)
        #expect(rates.recall == nil)
        #expect(rates.f1 == nil)
        #expect(rates.listItemAccuracy == nil)
        #expect(rates.overSegmentation == 0)
    }

    @Test("scores every laid-out reference perfectly against itself")
    func referenceScoresPerfectly() {
        let rates = StructureRates(Self.laidOutCases.map { StructureScore(output: $0.expected, for: $0) })
        #expect(rates.cases > 0)
        #expect(rates.recall == 1)
        #expect(rates.precision == 1)
        #expect(rates.breaksInsideSentence == 0)
    }

    @Test("writes the rules engine's rates exactly as recorded, so a lost break shows as a diff")
    func matchesBaseline() async throws {
        let report = try await Self.rulesReport()
        print(report.table)
        let differences = try Self.golden.compare(report.baseline, inputs: [:])
        #expect(
            differences.isEmpty,
            "\(differences.count) rates moved; rerun with \(GoldenFile.updateVariable)=1 if intended:\n\(differences.map(\.description).joined(separator: "\n"))"
        )
    }

    @Test("detects a joiner that drops every break and one that breaks inside sentences")
    func seededBrokenJoiner() async throws {
        let before = try await Self.rulesReport()
        let flattened = try await Self.rulesReport {
            $0.split(whereSeparator: \.isNewline).joined(separator: " ")
        }
        #expect(flattened.overall.outputBreaks == 0)
        #expect(flattened.overall.overSegmentation < before.overall.overSegmentation)
        #expect((before.overall.recall ?? 0) > 0)
        let split = try await Self.rulesReport { $0.replacingOccurrences(of: " the ", with: "\nthe ") }
        #expect(split.overall.breaksInsideSentence > before.overall.breaksInsideSentence)
        #expect(split.overall.overSegmentation > before.overall.overSegmentation)
        #expect((split.overall.precision ?? 1) < (before.overall.precision ?? 1))
    }
}
