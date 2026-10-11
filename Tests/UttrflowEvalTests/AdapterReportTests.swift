// Tests that per-adapter counts group by adapter and that the baseline gate fails on a worse run.
import Foundation
import Testing
import UttrflowCore

@testable import UttrflowEval

/// Checks the per-adapter report: grouping, the table, and the gate against a stored run.
@Suite("Adapter report")
struct AdapterReportTests {
    private func evaluated(_ id: String, adapter: String?, exact: String? = "a") -> EvaluationCase {
        EvaluationCase(
            id: id, category: .oneLineField, spoken: "a", expected: "a", expectedExact: exact,
            adapter: adapter.map { AdapterID(rawValue: $0) })
    }

    private func score(
        _ id: String, broke: [String] = [], invented: [String] = [], declined: Bool = false
    ) -> CaseScore {
        CaseScore(
            caseID: id, similarity: 1, keptEverythingRequired: true, lost: [], isExact: broke.isEmpty,
            declined: declined, invented: invented, brokeShape: broke)
    }

    private func report(hits: Int, added: Int = 0) -> AdapterReport {
        AdapterReport(
            label: "engine",
            rows: [
                .init(
                    adapter: "sql", cases: 5, exactCases: 5, exactHits: hits, addedTokens: added,
                    shapeViolations: 0)
            ])
    }

    @Test func casesGroupByAdapterAndCountExactHitsAndViolations() {
        let cases = [
            evaluated("s1", adapter: "sql"), evaluated("s2", adapter: "sql"),
            evaluated("s3", adapter: "sql", exact: nil), evaluated("p1", adapter: nil),
            evaluated("c1", adapter: "cli"),
        ]
        let scores = [
            score("s1"), score("s2", broke: ["is exactly \"a\""], invented: ["drop"]),
            score("s3", broke: ["begins with \"x\""]), score("p1"), score("c1", declined: true),
        ]
        let built = AdapterReport(label: "engine", cases: cases, scores: scores)
        #expect(built.rows.map(\.adapter) == ["sql"])
        let row = built.rows[0]
        #expect(row.cases == 3 && row.exactCases == 2 && row.exactHits == 1)
        #expect(row.addedTokens == 1 && row.shapeViolations == 2)
        #expect(row.exactMatchRate == 0.5)
        #expect(built.table.contains("sql: 3 cases, exact 1/2 (50.0%), added 1, shape violations 2"))
    }

    @Test func aRunWithNoAdapterCaseSaysSo() {
        #expect(AdapterReport(label: "engine", rows: []).table == "no case names an adapter")
    }

    @Test func theGatePassesAnEqualRunAndFailsOneWithFewerExactHits() {
        let baseline = report(hits: 5)
        #expect(report(hits: 5).worsened(against: baseline) == .success([]))
        #expect(report(hits: 4).worsened(against: baseline) == .success(["sql"]))
    }

    @Test func anAddedWordFailsTheGateWhateverTheBaselineHeld() {
        #expect(report(hits: 5, added: 1).worsened(against: report(hits: 5, added: 1)) == .success(["sql"]))
    }

    @Test func runsWithDifferentLabelsOrCaseCountsAreNotCompared() {
        let other = AdapterReport(label: "other", rows: report(hits: 5).rows)
        #expect(
            report(hits: 5).worsened(against: other)
                == .failure(.init(reason: "measured \"engine\", baseline \"other\"")))
        let fewer = AdapterReport(
            label: "engine",
            rows: [
                .init(
                    adapter: "sql", cases: 4, exactCases: 4, exactHits: 4, addedTokens: 0, shapeViolations: 0)
            ])
        #expect(report(hits: 5).worsened(against: fewer) != .success([]))
    }

    @Test func aStoredReportReadsBackEqual() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "adapter-report-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let stored = AdapterReport(
            label: "engine", recordedAt: Date(timeIntervalSince1970: 0), rows: report(hits: 3).rows)
        try stored.write(to: url)
        #expect(try AdapterReport.read(from: url) == stored)
    }
}
