// The regression gate every scorer shares: save, or compare with and print against, a stored baseline.
import ArgumentParser
private import Foundation
internal import UttrflowEval
internal import UttrflowSpeech

extension SpeechModel {
    /// The pins a revision bump changes, which a baseline refuses to be compared across; an unpinned folder has none.
    var recogniserPins: String? {
        guard !weightsRevision.isEmpty else { return nil }
        return "\(variant) weights \(weightsRevision) tokenizer \(tokenizerRevision)"
    }
}

/// Saves a run as the baseline, or compares it with the stored one and fails on a regression when asked.
struct BaselineGate {
    let path: String
    let saveBaseline: Bool
    let failOnRegression: Bool

    func judge(_ measured: AccuracyBaseline) throws {
        let url = URL(fileURLWithPath: path)
        if saveBaseline {
            try measured.write(to: url)
            print("\nBaseline written to \(path). Later runs are measured against it.")
            return
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CleanExit.message(
                "No baseline at \(path). Write one with --save-baseline once you are happy "
                    + "with these numbers.")
        }

        let stored = try AccuracyBaseline.read(from: url)
        let comparison = stored.compare(with: measured)
        printComparison(comparison, against: stored)

        if failOnRegression, comparison.failsGate { throw ExitCode.failure }
    }

    private func printComparison(_ comparison: BaselineComparison, against baseline: AccuracyBaseline) {
        print(
            "\n\nAgainst the baseline taken "
                + baseline.recordedAt.formatted(date: .abbreviated, time: .shortened)
                + " (\(baseline.label))")
        if let reason = comparison.reason {
            print("  no verdict: \(reason)")
            return
        }

        printChanges("overall", [comparison.overall])
        printChanges("by language", comparison.byLanguage)
        printChanges("by stress", comparison.byStress)
        printChanges("by cohort", comparison.byCohort)
        printChanges("by condition", comparison.byCondition)

        if !comparison.added.isEmpty || !comparison.removed.isEmpty {
            print(
                "\n  measured over the \(comparison.overall.referenceWordCount) words the two runs "
                    + "share: \(comparison.added.count) sample(s) are new since the baseline and "
                    + "\(comparison.removed.count) have gone.")
        }
        if !comparison.newlyUnscorable.isEmpty {
            print(
                "\n  \(comparison.newlyUnscorable.count) sample(s) used to produce a transcript and "
                    + "now produce nothing: "
                    + comparison.newlyUnscorable.prefix(5).joined(separator: ", "))
        }
        printMoved("worse", comparison.regressed)
        printMoved("better", comparison.improved)

        let overall = comparison.overall
        print(
            "\nverdict: \(comparison.verdict.rawValue)"
                + (overall.interval.map { "; overall change \(span($0))" } ?? "")
                + (overall.minimumDetectableChange.map {
                    String(format: ", smallest detectable %.1f pp", $0 * 100)
                }
                    ?? ""))
    }

    private func printChanges(_ heading: String, _ changes: [BaselineComparison.Change]) {
        guard !changes.isEmpty else { return }
        print(
            "\n" + heading.padded(to: 22) + "was".padded(to: 9) + "now".padded(to: 9)
                + "change".padded(to: 10) + "95% interval".padded(to: 20) + "detectable".padded(to: 12)
                + "words")
        for change in changes {
            let movement = change.delta.map { String(format: "%+.1f pp", $0 * 100) } ?? "n/a"
            print(
                change.label.padded(to: 22) + percent(change.before).padded(to: 9)
                    + percent(change.after).padded(to: 9) + movement.padded(to: 10)
                    + (change.interval.map(span) ?? "n/a").padded(to: 20)
                    + (change.minimumDetectableChange.map { String(format: "%.1f pp", $0 * 100) } ?? "n/a")
                    .padded(to: 12)
                    + "\(change.referenceWordCount)"
                    + (change.isUnderpowered ? "  (too few utterances to judge)" : "")
                    + (change.verdict == .worsened ? "  ← worse" : ""))
        }
    }

    /// A change interval in percentage points, the unit every delta is printed in.
    private func span(_ interval: ClosedRange<Double>) -> String {
        String(format: "%+.1f to %+.1f pp", interval.lowerBound * 100, interval.upperBound * 100)
    }

    /// Prints the individual samples that moved, capped, as evidence for the verdict.
    private func printMoved(_ direction: String, _ changes: [BaselineComparison.Change]) {
        guard !changes.isEmpty else { return }
        print("\n  \(changes.count) sample(s) \(direction), worst first:")
        for change in changes.prefix(10) {
            print(
                "    " + change.label.padded(to: 26) + percent(change.before).padded(to: 9) + "→ "
                    + percent(change.after))
        }
        if changes.count > 10 { print("    and \(changes.count - 10) more") }
    }

    private func percent(_ value: Double?) -> String {
        value.map { "\(String(format: "%.1f", $0 * 100))%" } ?? "n/a"
    }
}
