import Testing
import UttrflowAI
import UttrflowCore
import UttrflowTestSupport

@testable import UttrflowEval

/// Disfluency removal scored by the words deleted, per class, against the rates last recorded.
@Suite("Disfluency deletion")
struct DisfluencyDeletionTests {
    /// The rules engine's rates per class, as last recorded in `Golden/disfluency-deletion.golden`.
    static let golden = GoldenFile(suite: "disfluency-deletion")

    private static func rulesReport(
        rewriting: (String) -> String = { $0 }
    ) async throws -> DeletionReport {
        var scores: [DeletionScore] = []
        for testCase in EvaluationCorpus.disfluency {
            let result = try await RuleBasedTransformer().transform(testCase.evaluation.transformationRequest())
            scores.append(
                DeletionScore(
                    output: rewriting(result.text), for: testCase.evaluation, disfluency: testCase.disfluency,
                    record: result.cleaning))
        }
        return DeletionReport(scores: scores)
    }

    /// Drops the second of every doubled word, the seeded fault a stammer pass that ignores meaning would make.
    private static func deletingEveryDoubledWord(_ text: String) -> String {
        var kept: [Substring] = []
        for word in text.split(separator: " ") {
            if let last = kept.last, Scorer.tokens(String(last)) == Scorer.tokens(String(word)) { continue }
            kept.append(word)
        }
        return kept.joined(separator: " ")
    }

    @Test("counts a deletable word deleted, a fluent word deleted and a deletable word kept apart")
    func scoresOneCase() throws {
        let testCase = EvaluationCase(
            id: "seeded", category: .everyday, spoken: "um send the the report", expected: "Send the report.")
        let score = DeletionScore(output: "Send report.", for: testCase, disfluency: .repetition)
        #expect(score.goldDeleted.sorted() == ["the", "um"])
        #expect(score.deleted.sorted() == ["the", "the", "um"])
        #expect(score.correct == 2)
        #expect(score.overDeleted == 1)
        #expect(score.missed == 0)
        #expect(score.fluentWords == 3)
        let rates = DeletionRates([score])
        #expect(rates.precision == 2.0 / 3.0)
        #expect(rates.recall == 1)
        #expect(rates.overDeletion == 1.0 / 3.0)
    }

    @Test("reads a rewritten word as kept, so a numeral is not a deletion")
    func rewriteIsNotDeletion() {
        let testCase = EvaluationCase(
            id: "numeral", category: .everyday, spoken: "order four chairs", expected: "Order four chairs.")
        let score = DeletionScore(output: "Order 4 chairs.", for: testCase, disfluency: .fluentControl)
        #expect(score.deleted.isEmpty)
    }

    @Test("leaves precision and recall unset where nothing was deletable or deleted")
    func emptyRatesAreUnset() {
        let rates = DeletionRates([])
        #expect(rates.precision == nil)
        #expect(rates.recall == nil)
        #expect(rates.f1 == nil)
        #expect(rates.overDeletion == 0)
    }

    @Test("gives every class at least five cases, and no deletable word to a class kept by policy")
    func corpusShape() {
        for disfluency in DisfluencyClass.allCases {
            let cases = EvaluationCorpus.disfluency.filter { $0.disfluency == disfluency }
            #expect(cases.count >= 5, "\(disfluency) has \(cases.count) cases")
        }
        for testCase in EvaluationCorpus.disfluency {
            let deletable = DeletionScore(
                output: testCase.evaluation.expected, for: testCase.evaluation, disfluency: testCase.disfluency
            ).goldDeleted
            let keepsEverything = [.discourseMarker, .fluentControl].contains(testCase.disfluency)
            #expect(deletable.isEmpty == keepsEverything, "\(testCase.evaluation.id) deletes \(deletable)")
        }
        let ids = EvaluationCorpus.disfluency.map(\.evaluation.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("writes the rules engine's rates exactly as recorded, so a rise in over-deletion shows as a diff")
    func matchesBaseline() async throws {
        let report = try await Self.rulesReport()
        print(report.table)
        let differences = try Self.golden.compare(report.baseline, inputs: [:])
        #expect(
            differences.isEmpty,
            "\(differences.count) rates moved; rerun with \(GoldenFile.updateVariable)=1 if intended:\n\(differences.map(\.description).joined(separator: "\n"))"
        )
    }

    @Test("fails a change that raises the over-deletion rate above the recorded one")
    func overDeletionNeverRises() async throws {
        let recorded = try Self.golden.recorded()
        let report = try await Self.rulesReport()
        for (label, line) in report.baseline {
            let now = try #require(Self.overDeletion(in: line))
            let before = try #require(recorded[label].flatMap(Self.overDeletion(in:)), "\(label) is not recorded")
            #expect(now <= before, "\(label) over-deletion rose from \(before)% to \(now)%")
        }
    }

    @Test("raises over-deletion and lowers precision when every doubled word is deleted")
    func seededDoubledWordDeletion() async throws {
        let before = try await Self.rulesReport()
        let after = try await Self.rulesReport(rewriting: Self.deletingEveryDoubledWord)
        #expect(after.overall.overDeletion > before.overall.overDeletion)
        let precision = try #require(after.overall.precision)
        #expect(precision < (before.overall.precision ?? 1))
        // A doubled word the rules miss is deletable, so the fault can only add correct deletions.
        #expect(after.overall.correct >= before.overall.correct)
        let fluent = try #require(after.byClass.first { $0.disfluency == .fluentControl }?.rates)
        let fluentBefore = try #require(before.byClass.first { $0.disfluency == .fluentControl }?.rates)
        #expect(fluent.overDeletion > fluentBefore.overDeletion)
    }

    /// The over-deletion percentage a baseline line records.
    private static func overDeletion(in line: String) -> Double? {
        line.split(separator: " ").first { $0.hasPrefix("over-deletion=") }
            .flatMap { Double($0.dropFirst("over-deletion=".count).dropLast()) }
    }
}
