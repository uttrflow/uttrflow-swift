// Tests that a bake-off comparison is judged on held-out cases, not on the development cases a change is tuned on.
import Foundation
import Testing
@testable import UttrflowEval
@testable import uttrflow_bakeoff

struct SplitVerdictTests {
    /// Forty case ids from each split, found by the split's own rule.
    static let ids: (development: [String], heldOut: [String]) = {
        let all = (0..<1000).map { "case-\($0)" }
        return (
            Array(all.filter { CorpusSplit(caseID: $0) == .development }.prefix(40)),
            Array(all.filter { CorpusSplit(caseID: $0) == .heldout }.prefix(40))
        )
    }()

    static func measurement(passing: Set<String>) throws -> uttrflow_bakeoff.Measurement {
        let cases: [[String: Any]] = (ids.development + ids.heldOut).map { id in
            [
                "caseID": id, "category": "everyday", "similarity": 1.0, "lost": [String](),
                "passed": passing.contains(id), "declined": false,
            ]
        }
        let json: [String: Any] = [
            "description": [
                "name": "rules", "version": "—", "parameters": "—", "quantisation": "—", "size": "0",
            ],
            "report": [
                "passRate": 0.5, "meanSimilarity": 1.0, "medianSeconds": 0.0, "slowestSeconds": 0.0,
                "declinedCount": 0, "lostWordCount": 0, "cases": cases,
            ],
        ]
        return try JSONDecoder().decode(
            uttrflow_bakeoff.Measurement.self, from: JSONSerialization.data(withJSONObject: json))
    }

    /// Half of each split passes before the change.
    static let before = Set(ids.development.prefix(20) + ids.heldOut.prefix(20))

    @Test("memorising ten development cases raises development and is not shown better")
    func memorisedDevelopmentIsNotBetter() throws {
        let memorised = Self.before.union(Self.ids.development.suffix(10))
        let verdict = SplitVerdict.judge(
            try Self.measurement(passing: memorised), against: try Self.measurement(passing: Self.before))
        #expect(verdict.development.rose)
        #expect(verdict.heldOut.change == 0)
        #expect(verdict.outcome == .notShownBetter)
        #expect(verdict.lines.last == "Verdict on heldout: not shown better: the held-out score did not move")
    }

    @Test("a development gain paid for with held-out cases is over-fitted")
    func developmentGainWithHeldOutLossIsOverfitted() throws {
        let after = Self.before.union(Self.ids.development.suffix(10)).subtracting(
            Self.ids.heldOut.prefix(10))
        let verdict = SplitVerdict.judge(
            try Self.measurement(passing: after), against: try Self.measurement(passing: Self.before))
        #expect(verdict.outcome == .overfitted)
    }

    @Test("a held-out gain beyond the paired bound is better")
    func heldOutGainIsBetter() throws {
        let after = Self.before.union(Self.ids.heldOut.suffix(10))
        let verdict = SplitVerdict.judge(
            try Self.measurement(passing: after), against: try Self.measurement(passing: Self.before))
        #expect(verdict.outcome == .better)
    }

    @Test("one held-out case changing sits inside the bound")
    func singleFlipIsNotShownBetter() throws {
        let after = Self.before.union([Self.ids.heldOut[39]])
        let verdict = SplitVerdict.judge(
            try Self.measurement(passing: after), against: try Self.measurement(passing: Self.before))
        #expect(verdict.outcome == .notShownBetter)
    }
}
