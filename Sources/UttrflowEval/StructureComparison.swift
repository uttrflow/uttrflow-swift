// Two runs' layout over the same cases, judged per destination by a paired bootstrap over cases.
import Foundation
import UttrflowCore

/// How a later run's layout differs from an earlier run's on the cases both scored.
struct StructureComparison: Sendable, Equatable {
    /// A layout rate judged between runs, each a count over a total summed across cases.
    enum Measure: String, Sendable, CaseIterable {
        /// Reference breaks the output lacks: one less recall.
        case missedBreaks = "missed-breaks"
        /// Output breaks the reference lacks: one less precision.
        case wrongBreaks = "wrong-breaks"
        /// Reference list items the output does not open: one less list-item accuracy.
        case missedListItems = "missed-list-items"
        /// Output breaks per 100 output words, whose change is the change in over-segmentation.
        case breaksPerHundredWords = "breaks-per-100-words"

        func counts(_ score: StructureScore) -> (count: Int, total: Int) {
            switch self {
            case .missedBreaks: (score.referenceBreaks - score.correctBreaks, score.referenceBreaks)
            case .wrongBreaks: (score.outputBreaks - score.correctBreaks, score.outputBreaks)
            case .missedListItems:
                (score.referenceListItems - score.correctListItems, score.referenceListItems)
            case .breaksPerHundredWords: (score.outputBreaks, score.outputWords)
            }
        }

        var scale: Double {
            switch self {
            case .missedBreaks, .wrongBreaks, .missedListItems: 1
            case .breaksPerHundredWords: 100
            }
        }

        /// Whether a fall is better; breaks per 100 words is better nearer the reference, either way.
        var lowerIsBetter: Bool {
            switch self {
            case .missedBreaks, .wrongBreaks, .missedListItems: true
            case .breaksPerHundredWords: false
            }
        }

        func format(_ value: Double) -> String {
            switch self {
            case .missedBreaks, .wrongBreaks, .missedListItems: String(format: "%.1f%%", value * 100)
            case .breaksPerHundredWords: String(format: "%.2f", value)
            }
        }
    }

    /// One measure over one slice of cases, before and after.
    struct Change: Sendable, Equatable {
        let label: String
        let measure: Measure
        let cases: Int
        let before: Double?
        let after: Double?
        /// The interval for the change, in the measure's own scale; `nil` under two cases.
        let interval: ClosedRange<Double>?
        let minimumDetectableChange: Double?

        /// Improved or worsened by the interval; `nil` for a measure where neither direction is better.
        var verdict: BaselineComparison.Verdict? {
            measure.lowerIsBetter ? BaselineComparison.Verdict(errorRateChange: interval) : nil
        }
    }

    /// Each destination's changes in declaration order, then all cases together, every measure in each.
    let changes: [Change]

    /// Pairs the cases by identifier; a case scored in only one run is left out.
    init(before: StructureReport, after: StructureReport, method: PairedBootstrap = .standard) {
        let afterByID = Dictionary(after.scores.map { ($0.caseID, $0) }) { first, _ in first }
        let paired = before.scores.compactMap { was in afterByID[was.caseID].map { (was, $0) } }
        let slices =
            Destination.allCases.compactMap { destination in
                let cases = paired.filter { $0.0.destination == destination }
                return cases.isEmpty ? nil : (destination.rawValue, cases)
            } + [("all", paired)]
        changes = slices.flatMap { label, cases in
            Measure.allCases.map { Self.change(label, $0, cases, method) }
        }
    }

    private static func change(
        _ label: String, _ measure: Measure, _ cases: [(StructureScore, StructureScore)],
        _ method: PairedBootstrap
    ) -> Change {
        let pairs = cases.map { was, now in
            let (before, after) = (measure.counts(was), measure.counts(now))
            return PairedBootstrap.Pair(
                errorsBefore: before.count, wordsBefore: before.total, errorsAfter: after.count,
                wordsAfter: after.total)
        }
        let estimate = method.estimate(pairs)
        let scale = measure.scale
        return Change(
            label: label, measure: measure, cases: cases.count,
            before: rate(cases.map { measure.counts($0.0) }, scale),
            after: rate(cases.map { measure.counts($0.1) }, scale),
            interval: estimate.map { $0.interval.lowerBound * scale...$0.interval.upperBound * scale },
            minimumDetectableChange: estimate.map { $0.minimumDetectableChange * scale })
    }

    private static func rate(_ counts: [(count: Int, total: Int)], _ scale: Double) -> Double? {
        let total = counts.reduce(0) { $0 + $1.total }
        return total == 0 ? nil : Double(counts.reduce(0) { $0 + $1.count }) * scale / Double(total)
    }

    var table: String {
        changes.map { change in
            let measure = change.measure
            let values = [change.before, change.after].map { $0.map(measure.format) ?? "-" }
            let judged =
                change.interval.map { interval in
                    "[\(measure.format(interval.lowerBound)), \(measure.format(interval.upperBound))]"
                        + " mdc=\(measure.format(change.minimumDetectableChange ?? 0))"
                        + " \(change.verdict?.rawValue ?? "-")"
                } ?? (change.cases < 2 ? "too few cases to judge" : "nothing to count")
            return [
                change.label.padding(toLength: 14, withPad: " ", startingAt: 0),
                measure.rawValue.padding(toLength: 21, withPad: " ", startingAt: 0),
                "cases=\(change.cases)", "\(values[0]) -> \(values[1])", judged,
            ].joined(separator: " ")
        }
        .joined(separator: "\n")
    }
}
