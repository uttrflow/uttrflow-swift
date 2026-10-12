import Foundation
import Testing

@testable import UttrflowEval

/// Sweep feature indices are checked before scoring a synthetic table.
@Suite("Sweep feature bounds")
struct ThresholdSweepFeatureTests {
    static func sweep(feature: Int, grid: [Double] = ThresholdSweepTests.fine) throws -> ThresholdSweep {
        let (table, data) = ThresholdSweepTests.table(
            wrong: { 0.1 + 0.3 * $0 }, right: { 0.4 + 0.5 * $0 })
        return try ThresholdSweep(table: table, tableData: data, request: request(feature, grid: grid))
    }

    static func request(_ feature: Int, grid: [Double]) -> ThresholdSweep.Request {
        .init(
            parameter: "doubt", feature: feature, direction: .atOrBelow, grid: grid,
            falseFlagBound: 0.05, seed: "a")
    }

    @Test("A negative feature throws the column error")
    func negativeFeature() throws {
        #expect(throws: ThresholdSweep.Failure.noFeature(-1)) { try Self.sweep(feature: -1) }
    }

    @Test("The minimum signed feature throws the column error")
    func minimumFeature() throws {
        #expect(throws: ThresholdSweep.Failure.noFeature(Int.min)) { try Self.sweep(feature: Int.min) }
    }

    @Test("The upper bound remains a column error", arguments: [1, Int.max])
    func upperBound(feature: Int) throws {
        #expect(throws: ThresholdSweep.Failure.noFeature(feature)) { try Self.sweep(feature: feature) }
    }

    @Test("An empty table keeps its column error", arguments: [-1, 0, Int.max])
    func emptyTable(feature: Int) throws {
        let table = FitTable(featureSpecVersion: 1, rows: [])
        #expect(throws: ThresholdSweep.Failure.noFeature(feature)) {
            try ThresholdSweep(
                table: table, tableData: Data(), request: Self.request(feature, grid: [0.5]))
        }
    }

    @Test("An empty grid is refused before the feature", arguments: [-1, Int.min, 0, Int.max])
    func emptyGrid(feature: Int) throws {
        #expect(throws: ThresholdSweep.Failure.emptyGrid) { try Self.sweep(feature: feature, grid: []) }
    }

    @Test("Feature zero keeps the complete deterministic record and report")
    func validFeature() throws {
        let first = try Self.sweep(feature: 0)
        let repeated = try Self.sweep(feature: 0)
        #expect(first.record.feature == 0)
        #expect(first.record.verdict == .chosen)
        #expect(first.record.chosen == 0.4)
        #expect(try first.encoded() == repeated.encoded())
        #expect(first.report == repeated.report)
        #expect(first.report.filter { $0.hasPrefix("test:") }.count == 1)
    }
}
