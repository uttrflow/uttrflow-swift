import Foundation
import Testing

@testable import UttrflowEval

@Suite("Adapter report count validation")
struct AdapterReportCountValidationTests {
    private func decoded(
        _ counts: [String: Int] = [:], adapter: String = "sql", label: String = "synthetic", copies: Int = 1
    ) throws -> AdapterReport {
        var row: [String: Any] = [
            "adapter": adapter, "cases": 2, "exactCases": 2, "exactHits": 2,
            "addedTokens": 0, "shapeViolations": 0,
        ]
        for (key, value) in counts { row[key] = value }
        let data = try JSONSerialization.data(withJSONObject: [
            "label": label, "recordedAt": "2026-01-01T00:00:00Z",
            "rows": Array(repeating: row, count: copies),
        ])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AdapterReport.self, from: data)
    }

    private var invalidCounts: Result<[String], AdapterReport.Incomparable> {
        .failure(.init(reason: "adapter counts must be nonnegative with exactHits <= exactCases <= cases"))
    }

    @Test func savedNegativeAddedTokensCannotPassAsClean() throws {
        let report = try decoded(["addedTokens": -1])
        #expect(report.rows[0].addedTokens == -1)
        #expect(report.worsened(against: report) == invalidCounts)
    }

    @Test(arguments: [0, 1, 2, 3, 4, 5, 6])
    func everyImpossibleCountIsRejected(kind: Int) throws {
        let reports = [
            try decoded(["cases": -1, "exactCases": 0, "exactHits": 0]),
            try decoded(["exactCases": -1, "exactHits": 0]),
            try decoded(["exactHits": -1]),
            try decoded(["addedTokens": -1]),
            try decoded(["shapeViolations": -1]),
            try decoded(["exactCases": 3]),
            try decoded(["exactHits": 3]),
        ]
        let report = reports[kind]
        #expect(report.worsened(against: report) == invalidCounts)
    }

    private enum Side: CaseIterable { case measured, baseline }

    @Test(arguments: Side.allCases)
    private func invalidCountsInEitherReportAreRejected(side: Side) throws {
        let valid = try decoded()
        for invalid in [
            try decoded(["exactHits": -1]), try decoded(["exactHits": 3]),
            try decoded(["addedTokens": -1]), try decoded(["shapeViolations": -1]),
        ] {
            let result =
                switch side {
                case .baseline: valid.worsened(against: invalid)
                case .measured: invalid.worsened(against: valid)
                }
            #expect(result == invalidCounts)
        }
    }

    @Test func existingComparabilityFailuresKeepPrecedence() throws {
        let invalid = try decoded(["addedTokens": -1])
        #expect(
            invalid.worsened(against: try decoded(label: "other"))
                == .failure(.init(reason: "measured \"synthetic\", baseline \"other\"")))
        #expect(
            invalid.worsened(against: try decoded(copies: 2))
                == .failure(.init(reason: "adapter rows must have unique names in each report")))
        for baseline in [
            try decoded(adapter: "cli"), try decoded(["cases": 3]),
            try decoded(["exactCases": 1, "exactHits": 1]),
        ] {
            #expect(
                invalid.worsened(against: baseline)
                    == .failure(.init(reason: "the adapters or their case counts differ from the baseline's"))
            )
        }
    }

    @Test func validBoundaryCountsRemainComparable() throws {
        for report in [
            try decoded(["cases": 0, "exactCases": 0, "exactHits": 0]),
            try decoded(["exactCases": 0, "exactHits": 0]),
            try decoded(["cases": Int.max, "exactCases": Int.max, "exactHits": Int.max]),
        ] {
            #expect(report.worsened(against: report) == .success([]))
        }
        let empty = AdapterReport(label: "synthetic", rows: [])
        #expect(empty.worsened(against: empty) == .success([]))
        let baseline = try decoded()
        #expect(try decoded(["exactHits": 1]).worsened(against: baseline) == .success(["sql"]))
        for report in [
            try decoded(["addedTokens": 3]), try decoded(["shapeViolations": 3]),
            try decoded(["addedTokens": Int.max, "shapeViolations": Int.max]),
        ] {
            #expect(report.worsened(against: baseline) == .success(["sql"]))
            #expect(baseline.worsened(against: report) == .success([]))
        }
    }
}
