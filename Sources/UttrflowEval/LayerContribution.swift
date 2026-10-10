// What one degraded path costs against the default set: the paired change, its interval and a keep or remove verdict.
import Foundation
package import UttrflowCore

/// The marginal contribution of the layers one degraded path switches off. See `Docs/dictation-quality.md`.
package struct LayerContribution: Sendable, Equatable {
    package enum Verdict: String, Sendable {
        case keep
        case remove
    }

    /// The layers switched off, in declaration order.
    package let off: [QualityLayer]
    /// Failed-case rate with the layers off minus with them on; positive when the layers help.
    package let failedDelta: Double
    package let failedCases: PairedBootstrap.Estimate?
    /// Invented, deleted and lost words per reference word with the layers off minus on.
    package let meaningDelta: Double
    package let meaningErrors: PairedBootstrap.Estimate?
    /// Cases that fail with the layers on and pass with them off: the overrides the layers got wrong.
    package let brokeCases: Int
    package let cases: Int
    /// Mean wall-clock time per case the layers add; measured, so it never decides the verdict.
    package let addedLatency: Duration
    package let verdict: Verdict

    package var falseOverrideRate: Double { cases == 0 ? 0 : Double(brokeCases) / Double(cases) }

    /// Pairs `scores` (layers off) with `reference` (default set), case by case over `cases`.
    package init(
        off: [QualityLayer], scores: [CaseScore], reference: [CaseScore], cases: [EvaluationCase],
        latency: Duration, bootstrap: PairedBootstrap = .standard
    ) {
        let words = cases.map { max(1, Scorer.surfaceWords($0.expected).count) }
        let failed = zip(reference, scores).map {
            PairedBootstrap.Pair(
                errorsBefore: $0.passed ? 0 : 1, wordsBefore: 1, errorsAfter: $1.passed ? 0 : 1, wordsAfter: 1
            )
        }
        let meaning = zip(zip(reference, scores), words).map { pair, words in
            PairedBootstrap.Pair(
                errorsBefore: Self.meaningErrors(pair.0), wordsBefore: words,
                errorsAfter: Self.meaningErrors(pair.1), wordsAfter: words)
        }
        self.off = off
        self.failedDelta = Self.delta(failed)
        self.failedCases = bootstrap.estimate(failed)
        self.meaningDelta = Self.delta(meaning)
        self.meaningErrors = bootstrap.estimate(meaning)
        self.brokeCases = zip(reference, scores).count { !$0.passed && $1.passed }
        self.cases = scores.count
        self.addedLatency = latency
        let measures = Self.preventsHarm(off) ? [meaningErrors] : [failedCases, meaningErrors]
        let improves = measures.contains { ($0?.interval.lowerBound ?? 0) > 0 }
        let harms = measures.contains { ($0?.interval.upperBound ?? 0) < 0 }
        self.verdict = improves && !harms ? .keep : .remove
    }

    /// Whether every layer switched off exists to prevent harm, so the harm it prevents is its measure.
    package static func preventsHarm(_ layers: [QualityLayer]) -> Bool {
        !layers.isEmpty && layers.allSatisfy { $0 == .overrideGate }
    }

    /// The words of one output that change what the reference means.
    static func meaningErrors(_ score: CaseScore) -> Int {
        score.invented.count + score.deleted.count + score.lost.count
    }

    private static func delta(_ pairs: [PairedBootstrap.Pair]) -> Double {
        let before = pairs.reduce(into: (0, 0)) { $0 = ($0.0 + $1.errorsBefore, $0.1 + $1.wordsBefore) }
        let after = pairs.reduce(into: (0, 0)) { $0 = ($0.0 + $1.errorsAfter, $0.1 + $1.wordsAfter) }
        guard before.1 > 0, after.1 > 0 else { return 0 }
        return Double(after.0) / Double(after.1) - Double(before.0) / Double(before.1)
    }

    /// The rows as a Markdown table; `latency` adds the measured column, which a generated page leaves out.
    package static func table(_ rows: [LayerContribution], latency: Bool) -> String {
        var header =
            "| Off | Failed cases (pp) | Interval | MDC | Meaning errors (pp) | Interval | MDC | False overrides |"
        var rule = "|---|---|---|---|---|---|---|---|"
        if latency {
            header += " Added latency |"
            rule += "---|"
        }
        header += " Verdict |"
        rule += "---|"
        var lines = [header, rule]
        for row in rows {
            var cells = [
                row.off.map(\.rawValue).joined(separator: " + "), points(row.failedDelta),
                interval(row.failedCases), mdc(row.failedCases), points(row.meaningDelta),
                interval(row.meaningErrors), mdc(row.meaningErrors),
                "\(row.brokeCases) (\(points(row.falseOverrideRate)))",
            ]
            if latency { cells.append(milliseconds(row.addedLatency)) }
            cells.append(row.verdict.rawValue)
            lines.append("| " + cells.joined(separator: " | ") + " |")
        }
        return lines.joined(separator: "\n")
    }

    private static func points(_ rate: Double) -> String {
        let value = (rate * 10_000).rounded() / 100
        return value == 0 ? "0.00" : (value > 0 ? "+" : "") + String(format: "%.2f", value)
    }

    private static func interval(_ estimate: PairedBootstrap.Estimate?) -> String {
        guard let estimate else { return "none" }
        return "[\(points(estimate.interval.lowerBound)), \(points(estimate.interval.upperBound))]"
    }

    private static func mdc(_ estimate: PairedBootstrap.Estimate?) -> String {
        estimate.map { points($0.minimumDetectableChange) } ?? "none"
    }

    private static func milliseconds(_ duration: Duration) -> String {
        let parts = duration.components
        let value = Double(parts.seconds) * 1_000 + Double(parts.attoseconds) / 1e15
        return String(format: "%.3f ms", value)
    }
}
