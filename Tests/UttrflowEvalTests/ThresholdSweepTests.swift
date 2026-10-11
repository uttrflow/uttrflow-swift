import Foundation
import Testing

@testable import UttrflowEval

/// One sweep runner chooses a threshold on the calibration side and keeps the evidence.
@Suite("Threshold sweep")
struct ThresholdSweepTests {
    static let steps = 200

    /// Wrong rows read `wrong(u)` and right rows `right(u)` for `u` stepping through [0, 1), on both sides of the split.
    static func table(wrong: (Double) -> Double, right: (Double) -> Double) -> (FitTable, Data) {
        var rows: [FitTableRow] = []
        for split in CorpusSplit.allCases {
            for label in FitLabelClass.allCases {
                for step in 0..<steps {
                    let unit = Double(step) / Double(steps)
                    rows.append(
                        FitTableRow(
                            ordinal: rows.count, split: split, language: .english, label: label,
                            features: [label == .wrong ? wrong(unit) : right(unit)]))
                }
            }
        }
        let table = FitTable(featureSpecVersion: 1, rows: rows)
        return (table, (try? table.encoded()) ?? Data())
    }

    static func request(
        grid: [Double], margin: Int = 0, seed: String = "a"
    ) -> ThresholdSweep.Request {
        .init(
            parameter: "doubt", feature: 0, direction: .atOrBelow, grid: grid, falseFlagBound: 0.05,
            seed: seed, marginSteps: margin)
    }

    static let fine = (30...46).map { Double($0) / 100 }

    @Test("A flat optimum is chosen and its neighbours are kept")
    func flatOptimum() throws {
        let (table, data) = Self.table(wrong: { 0.1 + 0.3 * $0 }, right: { 0.4 + 0.5 * $0 })
        let sweep = try ThresholdSweep(table: table, tableData: data, request: Self.request(grid: Self.fine))
        #expect(sweep.record.verdict == .chosen)
        #expect(sweep.record.chosen == 0.4)
        #expect(sweep.record.neighbours.map(\.value) == [0.39, 0.41])
        #expect(sweep.record.trials.count == Self.fine.count)
        #expect(sweep.record.test?.missed == 0)
    }

    @Test("Running again writes an identical file")
    func deterministic() throws {
        let (table, data) = Self.table(wrong: { 0.1 + 0.3 * $0 }, right: { 0.4 + 0.5 * $0 })
        let first = try ThresholdSweep(table: table, tableData: data, request: Self.request(grid: Self.fine))
        let second = try ThresholdSweep(table: table, tableData: data, request: Self.request(grid: Self.fine))
        #expect(try first.encoded() == second.encoded())
        #expect(!first.record.id.isEmpty)
        #expect(first.record.tableDigest.hasPrefix("sha256:"))
    }

    @Test("A deliberately sharp optimum is flagged and refused until a margin is added")
    func cliff() throws {
        let (table, data) = Self.table(wrong: { _ in 0.3 }, right: { 0.4 + 0.5 * $0 })
        let grid = [0.25, 0.3, 0.35, 0.4]
        let refused = try ThresholdSweep(table: table, tableData: data, request: Self.request(grid: grid))
        #expect(refused.record.verdict == .cliff)
        #expect(refused.record.chosen == nil)
        #expect(refused.record.test == nil)
        let margin = try ThresholdSweep(
            table: table, tableData: data, request: Self.request(grid: grid, margin: 1))
        #expect(margin.record.verdict == .chosen)
        #expect(margin.record.chosen == 0.35)
    }

    @Test("A bound no grid value holds is infeasible")
    func infeasible() throws {
        let (table, data) = Self.table(wrong: { 0.5 + 0.4 * $0 }, right: { 0.1 + 0.8 * $0 })
        let sweep = try ThresholdSweep(
            table: table, tableData: data, request: Self.request(grid: [0.7, 0.8, 0.9]))
        #expect(sweep.record.verdict == .infeasible)
        #expect(sweep.report.last == "no grid value holds the bound")
    }

    @Test("The test side is scored once and cannot move the choice")
    func testSideIgnored() throws {
        let (table, data) = Self.table(wrong: { 0.1 + 0.3 * $0 }, right: { 0.4 + 0.5 * $0 })
        let base = try ThresholdSweep(table: table, tableData: data, request: Self.request(grid: Self.fine))
        let altered = FitTable(
            featureSpecVersion: 1,
            rows: table.rows.map { row in
                guard row.split == .heldout, ThresholdSweep.isTest(row, seed: "a") else { return row }
                return FitTableRow(
                    ordinal: row.ordinal, split: row.split, language: row.language, label: row.label,
                    features: [row.label == .wrong ? 0.99 : 0.01])
            })
        let moved = try ThresholdSweep(
            table: altered, tableData: (try? altered.encoded()) ?? Data(),
            request: Self.request(grid: Self.fine))
        #expect(moved.record.chosen == base.record.chosen)
        #expect(moved.record.test != base.record.test)
        #expect(base.report.filter { $0.hasPrefix("test:") }.count == 1)
    }

    @Test("Flagging at or above reverses which side is strict")
    func above() throws {
        let (table, data) = Self.table(wrong: { 0.6 + 0.3 * $0 }, right: { 0.1 + 0.5 * $0 })
        let request = ThresholdSweep.Request(
            parameter: "high", feature: 0, direction: .atOrAbove, grid: (54...70).map { Double($0) / 100 },
            falseFlagBound: 0.05, seed: "a")
        let sweep = try ThresholdSweep(table: table, tableData: data, request: request)
        #expect(sweep.record.chosen == 0.6)
    }

    @Test("A sweep with no grid, no column or a one-label side cannot run")
    func refusals() throws {
        let (table, data) = Self.table(wrong: { $0 }, right: { $0 })
        #expect(throws: ThresholdSweep.Failure.emptyGrid) {
            try ThresholdSweep(table: table, tableData: data, request: Self.request(grid: []))
        }
        let column = ThresholdSweep.Request(
            parameter: "x", feature: 3, direction: .atOrBelow, grid: [0.5], falseFlagBound: 0.1, seed: "a")
        #expect(throws: ThresholdSweep.Failure.noFeature(3)) {
            try ThresholdSweep(table: table, tableData: data, request: column)
        }
        let lonely = FitTable(
            featureSpecVersion: 1,
            rows: [
                FitTableRow(ordinal: 0, split: .development, language: .english, label: .right, features: [0])
            ])
        #expect(throws: ThresholdSweep.Failure.emptySide("fit")) {
            try ThresholdSweep(table: lonely, tableData: Data(), request: Self.request(grid: [0.5]))
        }
        #expect(ThresholdSweep.Failure.emptySide("fit").description.contains("fit"))
    }
}
