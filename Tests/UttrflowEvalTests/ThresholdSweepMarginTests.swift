import Foundation
import Testing

@testable import UttrflowEval

@Suite("Threshold sweep margin arithmetic")
struct ThresholdSweepMarginTests {
    @Test("a maximal forward margin reaches the endpoint without overflowing")
    func maximalForward() throws {
        let sweep = try sweep(direction: .atOrBelow, margin: Int.max)
        #expect(sweep.record.verdict == .chosen)
        #expect(sweep.record.chosen == 0.4)
        #expect(sweep.record.marginSteps == Int.max)
        #expect(try JSONDecoder().decode(ThresholdSweep.Record.self, from: sweep.encoded()) == sweep.record)
    }

    @Test("a maximal backward margin reaches the opposite endpoint")
    func maximalBackward() throws {
        let sweep = try sweep(direction: .atOrAbove, margin: Int.max)
        #expect(sweep.record.verdict == .chosen)
        #expect(sweep.record.chosen == 0.6)
        #expect(sweep.record.marginSteps == Int.max)
    }

    @Test(
        "ordinary and boundary margins retain the old clamped result",
        arguments: [ThresholdSweep.Direction.atOrBelow, .atOrAbove], [1, 2, 3, 4, 16])
    func boundedMargins(direction: ThresholdSweep.Direction, margin: Int) throws {
        let sweep = try sweep(direction: direction, margin: margin)
        let best = direction == .atOrBelow ? 1 : 2
        let sign = direction == .atOrBelow ? 1 : -1
        let oldIndex = min(max(best + sign * margin, 0), sweep.record.grid.count - 1)
        #expect(sweep.record.verdict == .chosen)
        #expect(sweep.record.chosen == sweep.record.grid[oldIndex])
        #expect(sweep.record.marginSteps == margin)
    }

    @Test(
        "a zero or negative margin still refuses a cliff",
        arguments: [ThresholdSweep.Direction.atOrBelow, .atOrAbove], [0, -1])
    func refusedMargins(direction: ThresholdSweep.Direction, margin: Int) throws {
        let sweep = try sweep(direction: direction, margin: margin)
        #expect(sweep.record.verdict == .cliff)
        #expect(sweep.record.chosen == nil)
        #expect(sweep.record.test == nil)
    }

    private func sweep(direction: ThresholdSweep.Direction, margin: Int) throws -> ThresholdSweep {
        let wrong = direction == .atOrBelow ? 0.3 : 0.7
        let start = direction == .atOrBelow ? 0.4 : 0.1
        let (table, data) = ThresholdSweepTests.table(wrong: { _ in wrong }, right: { start + 0.5 * $0 })
        let grid = direction == .atOrBelow ? [0.25, 0.3, 0.35, 0.4] : [0.6, 0.65, 0.7, 0.75]
        let request = ThresholdSweep.Request(
            parameter: "doubt", feature: 0, direction: direction, grid: grid, falseFlagBound: 0.05,
            seed: "a", marginSteps: margin)
        return try ThresholdSweep(table: table, tableData: data, request: request)
    }
}
