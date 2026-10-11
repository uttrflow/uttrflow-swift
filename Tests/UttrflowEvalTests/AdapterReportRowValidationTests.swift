// Checks decoded adapter reports reject duplicate row names without terminating the comparison.
import Foundation
import Testing

@testable import UttrflowEval

/// Exercises row identity validation at the saved-report boundary.
@Suite("Adapter report row validation")
struct AdapterReportRowValidationTests {
    private let row = """
        {"adapter":"sql","cases":2,"exactCases":2,"exactHits":2,"addedTokens":0,"shapeViolations":0}
        """

    private func decoded(rows: String, label: String = "synthetic") throws -> AdapterReport {
        let json = """
            {"label":"\(label)","recordedAt":"2026-01-01T00:00:00Z","rows":[\(rows)]}
            """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AdapterReport.self, from: Data(json.utf8))
    }

    private var duplicateFailure: Result<[String], AdapterReport.Incomparable> {
        .failure(.init(reason: "adapter rows must have unique names in each report"))
    }

    @Test func duplicateBaselineRowsAreIncomparable() throws {
        let baseline = try decoded(rows: "\(row),\(row)")
        let measured = try decoded(rows: row)
        #expect(baseline.rows.count == 2)
        #expect(measured.worsened(against: baseline) == duplicateFailure)
    }

    @Test func duplicateMeasuredRowsAreIncomparable() throws {
        let baseline = try decoded(rows: row)
        let measured = try decoded(rows: "\(row),\(row)")
        #expect(measured.rows.count == 2)
        #expect(measured.worsened(against: baseline) == duplicateFailure)
    }

    @Test func duplicatesInBothReportsAreIncomparable() throws {
        let duplicated = try decoded(rows: "\(row),\(row)")
        #expect(duplicated.worsened(against: duplicated) == duplicateFailure)
    }

    @Test func labelMismatchRetainsPrecedenceOverDuplicateRows() throws {
        let baseline = try decoded(rows: "\(row),\(row)", label: "other")
        let measured = try decoded(rows: row)
        #expect(
            measured.worsened(against: baseline)
                == .failure(.init(reason: "measured \"synthetic\", baseline \"other\"")))
    }

    @Test func uniqueDecodedRowsRetainHitRegression() throws {
        let baseline = try decoded(rows: row)
        let measured = try decoded(
            rows: row.replacingOccurrences(of: "\"exactHits\":2", with: "\"exactHits\":1"))
        #expect(baseline.worsened(against: baseline) == .success([]))
        #expect(measured.worsened(against: baseline) == .success(["sql"]))
    }
}
