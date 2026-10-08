import Foundation
import UttrflowEval

/// Judges a change by its held-out score, so a gain that only tuning on development cases buys is not called better. See `Docs/bakeoff-method.md`.
struct SplitVerdict: Equatable {
    /// How a split's pass rate changes, paired case by case over the cases both runs judged.
    struct Shift: Equatable {
        let split: CorpusSplit
        let cases: Int
        /// Change in pass rate, as a fraction of `cases`.
        let change: Double
        /// Half-width of the paired 95% interval around `change`.
        let bound: Double

        var lower: Double { change - bound }
        var upper: Double { change + bound }
        var rose: Bool { cases > 0 && lower > 0 }
        var fell: Bool { cases > 0 && upper < 0 }
    }

    enum Outcome: String, Equatable {
        case better = "better: the held-out score rose"
        case notShownBetter = "not shown better: the held-out score did not move"
        case worse = "worse: the held-out score fell"
        case overfitted = "over-fitted: the development score rose and the held-out score fell"
    }

    let development: Shift
    let heldOut: Shift

    var outcome: Outcome {
        if heldOut.fell { return development.change > 0 ? .overfitted : .worse }
        return heldOut.rose ? .better : .notShownBetter
    }

    /// Two-sided 95% normal quantile for the paired interval.
    static let z = 1.96

    /// Pairs each case judged in both runs with an unchanged fingerprint and neither run declining it.
    static func judge(_ current: Measurement, against baseline: Measurement) -> SplitVerdict {
        let previous = Dictionary(uniqueKeysWithValues: baseline.report.cases.map { ($0.caseID, $0) })
        var differences: [CorpusSplit: [Double]] = [:]
        for new in current.report.cases {
            guard let old = previous[new.caseID], !old.declined, !new.declined else { continue }
            if let before = old.identity, let after = new.identity, before != after { continue }
            let difference = Double(new.passed ? 1 : 0) - Double(old.passed ? 1 : 0)
            differences[CorpusSplit(caseID: new.caseID), default: []].append(difference)
        }
        return SplitVerdict(
            development: shift(.development, differences[.development] ?? []),
            heldOut: shift(.heldout, differences[.heldout] ?? []))
    }

    static func shift(_ split: CorpusSplit, _ differences: [Double]) -> Shift {
        let count = Double(differences.count)
        guard count > 1 else {
            return Shift(
                split: split, cases: differences.count, change: differences.first ?? 0, bound: .infinity)
        }
        let mean = differences.reduce(0, +) / count
        let variance = differences.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / (count - 1)
        return Shift(
            split: split, cases: differences.count, change: mean, bound: z * (variance / count).squareRoot())
    }

    /// The development line, the held-out line, the gap and the outcome, each naming its split.
    var lines: [String] {
        let gap = development.change - heldOut.change
        return [
            "\nScore by split, paired over cases both runs judged (95% interval):",
            Self.line(development), Self.line(heldOut),
            "  gap (development minus heldout): \(Self.points(gap))",
            "Verdict on \(heldOut.split.rawValue): \(outcome.rawValue)",
        ]
    }

    private static func line(_ shift: Shift) -> String {
        let interval =
            shift.bound.isFinite
            ? "[\(points(shift.lower)), \(points(shift.upper))]" : "[too few cases to bound]"
        return
            "  \(shift.split.rawValue.padded(to: 12)) \(shift.cases) cases, \(points(shift.change)) \(interval)"
    }

    private static func points(_ fraction: Double) -> String { String(format: "%+.1f pts", fraction * 100) }
}
