import Foundation
import Testing

@testable import UttrflowEval

@Suite("Adapter report comparability")
struct AdapterReportComparabilityTests {
    private func report(exactCases: Int, hits: Int) -> AdapterReport {
        AdapterReport(
            label: "fixture", recordedAt: Date(timeIntervalSince1970: 0),
            rows: [
                .init(
                    adapter: "sql", cases: 10, exactCases: exactCases, exactHits: hits,
                    addedTokens: 0, shapeViolations: 0)
            ])
    }

    @Test("a changed exact-case denominator cannot produce a comparable gate result", arguments: [5, 10])
    func changedDenominatorIsIncomparable(baselineExactCases: Int) {
        let baseline = report(exactCases: baselineExactCases, hits: 5)
        let measured = report(exactCases: 15 - baselineExactCases, hits: 5)
        #expect(measured.rows[0].exactMatchRate != baseline.rows[0].exactMatchRate)
        guard case .failure = measured.worsened(against: baseline) else {
            Issue.record("The gate compares different exact-case denominators")
            return
        }
    }

    @Test("equal denominators still compare exact hits", arguments: [4, 5])
    func equalDenominatorKeepsTheHitGate(hits: Int) {
        let baseline = report(exactCases: 5, hits: 5)
        let measured = report(exactCases: 5, hits: hits)
        #expect(measured.worsened(against: baseline) == .success(hits == 5 ? [] : ["sql"]))
    }
}
