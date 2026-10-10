// Chooses the override gate's threshold with a stated bound on the false-override rate, from counts alone.

import Foundation

/// The one-sided Clopper-Pearson upper bound on a rate seen as `failures` in `trials`.
package enum RiskBound {
    /// The largest rate at which seeing `failures` or fewer in `trials` still has probability `1 - confidence`.
    package static func upperBound(failures: Int, trials: Int, confidence: Double) -> Double {
        guard trials > 0, failures < trials else { return 1 }
        let tail = 1 - confidence
        var low = 0.0
        var high = 1.0
        for _ in 0..<100 {
            let middle = (low + high) / 2
            if atMost(failures, of: trials, rate: middle) > tail { low = middle } else { high = middle }
        }
        return high
    }

    /// The fewest trials whose bound with no failure is at or below `target`.
    package static func trialsToCertify(_ target: Double, confidence: Double) -> Int {
        guard target > 0, target < 1 else { return target >= 1 ? 1 : Int.max }
        return Int((log(1 - confidence) / log(1 - target)).rounded(.up))
    }

    /// The probability of `failures` or fewer in `trials` at `rate`, each term built from the last in log space.
    static func atMost(_ failures: Int, of trials: Int, rate: Double) -> Double {
        guard rate > 0 else { return 1 }
        guard rate < 1 else { return failures >= trials ? 1 : 0 }
        let odds = log(rate) - log1p(-rate)
        var logTerm = Double(trials) * log1p(-rate)
        var total = exp(logTerm)
        for count in stride(from: 1, through: failures, by: 1) {
            logTerm += log(Double(trials - count + 1)) - log(Double(count)) + odds
            total += exp(logTerm)
        }
        return min(1, total)
    }
}

/// The override gate's threshold chosen on held-out decisions by fixed-sequence testing; see Docs/dictation-quality.md.
package struct GateCalibration: Sendable, Equatable {
    /// One threshold of the grid: the overrides it applies, how many were wrong, and the bound on that rate.
    package struct Step: Sendable, Equatable {
        package let threshold: Double
        package let overrides: Int
        package let wrong: Int
        package let upperBound: Double

        /// The rate seen, never printed without `upperBound`.
        package var observedRate: Double { overrides == 0 ? 0 : Double(wrong) / Double(overrides) }
    }

    package let target: Double
    package let confidence: Double
    /// Every candidate the gate weighed on the split.
    package let decisions: Int
    /// The grid, strictest threshold first.
    package let steps: [Step]
    /// The loosest threshold of the run of tested steps, strictest first, that all held the target; `nil` when none did.
    package let certified: Step?

    /// Weighs `scores`, where a candidate is applied when its score is at or above the threshold and `wrong` marks a false override.
    package init(scores: [Double], wrong: [Bool], target: Double, confidence: Double = 0.95) {
        self.target = target
        self.confidence = confidence
        decisions = scores.count
        let ranked = zip(scores, wrong).sorted { $0.0 > $1.0 }
        var steps: [Step] = []
        var overrides = 0
        var wrongCount = 0
        for (index, pair) in ranked.enumerated() {
            overrides += 1
            if pair.1 { wrongCount += 1 }
            guard index == ranked.count - 1 || ranked[index + 1].0 != pair.0 else { continue }
            steps.append(
                Step(
                    threshold: pair.0, overrides: overrides, wrong: wrongCount,
                    upperBound: RiskBound.upperBound(
                        failures: wrongCount, trials: overrides, confidence: confidence)))
        }
        self.steps = steps
        let floor = RiskBound.trialsToCertify(target, confidence: confidence)
        certified = steps.filter { $0.overrides >= floor }.prefix { $0.upperBound <= target }.last
    }

    /// The threshold that ships: the certified one, else the strictest of the grid.
    package var shipped: Step? { certified ?? steps.first }

    /// The rate the shipped threshold is certified at: the target when it held, else the strictest step's own bound.
    package var certifiedRate: Double { certified == nil ? (steps.first?.upperBound ?? 1) : target }

    /// The smallest target this split could certify: every candidate applied and none wrong.
    package var smallestCertifiableTarget: Double {
        RiskBound.upperBound(failures: 0, trials: decisions, confidence: confidence)
    }

    /// The report `uttrflow-eval calibrate-gate` prints; every rate carries its bound.
    package var report: [String] {
        let level = percent(confidence)
        var lines = [
            "decisions weighed: \(decisions); target \(percent(target)) false overrides at \(level) confidence",
            "smallest target this split can certify: \(percent(smallestCertifiableTarget))"
                + " (\(RiskBound.trialsToCertify(target, confidence: confidence)) overrides with none wrong certify the target)",
        ]
        lines += steps.map { "threshold \(number($0.threshold)): \(describe($0))" }
        guard let shipped else { return lines + ["no decisions: nothing to certify"] }
        if certified != nil {
            lines.append(
                "certified at \(percent(target)): threshold \(number(shipped.threshold)), \(describe(shipped))"
            )
        } else {
            lines.append(
                "not certified at \(percent(target)); ships the strictest threshold \(number(shipped.threshold)),"
                    + " certified only at \(percent(certifiedRate)): \(describe(shipped))")
        }
        return lines
    }

    private func describe(_ step: Step) -> String {
        "\(step.wrong) of \(step.overrides) overrides wrong (\(percent(step.observedRate))),"
            + " at most \(percent(step.upperBound)) at \(percent(confidence))"
    }

    private func percent(_ value: Double) -> String { String(format: "%.2f%%", value * 100) }

    private func number(_ value: Double) -> String { String(format: "%g", value) }
}
