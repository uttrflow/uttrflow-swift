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

    private func change(
        _ comparison: StructureComparison, _ label: String, _ measure: StructureComparison.Measure
    ) throws -> StructureComparison.Change {
        try #require(comparison.changes.first { $0.label == label && $0.measure == measure })
    }

    @Test("gives a hand-computed change a zero-width interval at exactly that change")
    func knownExample() throws {
        let reference = "The trip is booked.\n\nThe hotel is near the station.\nWe leave at nine."
        let cases = (1...3).map {
            EvaluationCase(
                id: "case\($0)", category: .everyday, spoken: "spoken", expected: reference,
                destination: .document)
        }
        let before = StructureReport(scores: cases.map { StructureScore(output: reference, for: $0) })
        let dropped = "The trip is booked.\n\nThe hotel is near the station. We leave at nine."
        let after = StructureReport(scores: cases.map { StructureScore(output: dropped, for: $0) })
        let comparison = StructureComparison(before: before, after: after)
        let missed = try change(comparison, "document", .missedBreaks)
        #expect(missed.before == 0)
        #expect(missed.after == 0.5)
        #expect(missed.interval == 0.5...0.5)
        #expect(missed.minimumDetectableChange == 0)
        #expect(missed.verdict == .worsened)
        let wrong = try change(comparison, "document", .wrongBreaks)
        #expect(wrong.interval == 0...0)
        #expect(wrong.verdict == .unchanged)
        let density = try change(comparison, "all", .breaksPerHundredWords)
        let densityInterval = try #require(density.interval)
        #expect(abs(densityInterval.lowerBound + 100.0 / 14) < 1e-9)
        #expect(abs(densityInterval.upperBound + 100.0 / 14) < 1e-9)
        #expect(density.verdict == nil)
    }

    @Test("finds no change between identical runs and judges no destination with a single case")
    func identicalRuns() async throws {
        let report = try await Self.rulesReport()
        let comparison = StructureComparison(before: report, after: report)
        #expect(comparison.changes.count == (report.byDestination.count + 1) * 4)
        for change in comparison.changes {
            #expect(change.interval == nil || change.interval == 0...0, "\(change.label) \(change.measure)")
            #expect(change.verdict != .worsened && change.verdict != .improved)
        }
        #expect(comparison.changes.filter { $0.label == "all" }.allSatisfy { $0.interval == 0...0 })
        let single = try change(comparison, "sqlEditor", .missedBreaks)
        #expect(single.interval == nil)
        #expect(single.verdict == .unchanged)
    }

    @Test("judges a joiner that drops or adds breaks worse beyond its paired interval")
    func pairedVerdictOnBrokenJoiner() async throws {
        let before = try await Self.rulesReport()
        let flat = try await Self.rulesReport { $0.split(whereSeparator: \.isNewline).joined(separator: " ") }
        let flattened = StructureComparison(before: before, after: flat)
        #expect(try change(flattened, "all", .missedBreaks).verdict == .worsened)
        let fewer = try #require(try change(flattened, "all", .breaksPerHundredWords).interval)
        #expect(fewer.upperBound < 0)
        let split = StructureComparison(
            before: before,
            after: try await Self.rulesReport { $0.replacingOccurrences(of: " the ", with: "\nthe ") })
        #expect(try change(split, "all", .wrongBreaks).verdict == .worsened)
        let more = try #require(try change(split, "all", .breaksPerHundredWords).interval)
        #expect(more.lowerBound > 0)
        print(split.table)
    }
}
