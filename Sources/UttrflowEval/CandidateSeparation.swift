// How well a per-candidate score tells the meant word of a homophone slot from its rival.
private import Foundation

/// Separation of the meant word from its rival by forced score, greedy-step margin, or both. See `Docs/relisten-probe.md`.
package enum CandidateSeparation {
    /// One slot: the meant word's forced score minus the rival's, and each candidate's greedy-step margin.
    package struct Slot: Sendable, Equatable {
        package let forcedDifference: Double
        package let meantMargin: Double
        package let otherMargin: Double
        package let cluster: String

        package init(forcedDifference: Double, meantMargin: Double, otherMargin: Double, cluster: String) {
            self.forcedDifference = forcedDifference
            self.meantMargin = meantMargin
            self.otherMargin = otherMargin
            self.cluster = cluster
        }
    }

    /// The score a candidate is ranked by.
    package enum Feature: String, CaseIterable, Sendable {
        case forced = "forced score"
        case greedyMargin = "greedy-step margin"
        case both = "both, each over its standard deviation"
    }

    /// The leader and runner-up of one decoder step, which give a candidate token its greedy-step margin.
    package struct GreedyStep: Sendable, Equatable {
        package let leader: Int
        package let leaderScore: Float
        package let runnerUpScore: Float

        /// Reads the two highest of one step's log-probabilities; nil with fewer than two tokens.
        package init?(logProbabilities: [Float]) {
            guard logProbabilities.count >= 2 else { return nil }
            var leader = 0
            var leaderScore = -Float.infinity
            var runnerUpScore = -Float.infinity
            for (token, score) in logProbabilities.enumerated() {
                if score > leaderScore {
                    runnerUpScore = leaderScore
                    leader = token
                    leaderScore = score
                } else if score > runnerUpScore {
                    runnerUpScore = score
                }
            }
            self.leader = leader
            self.leaderScore = leaderScore
            self.runnerUpScore = runnerUpScore
        }

        /// The top-two gap when `token` leads the step, otherwise how far its log-probability trails the leader.
        package func margin(of token: Int, logProbability: Float) -> Float {
            token == leader ? leaderScore - runnerUpScore : logProbability - leaderScore
        }
    }

    /// Position of the first token where two candidates differ; nil when one candidate's tokens begin the other's.
    package static func firstDifference(_ first: [Int], _ second: [Int]) -> Int? {
        zip(first.indices, zip(first, second)).first { $0.1.0 != $0.1.1 }?.0
    }

    /// Both candidates of every slot scored by `feature`, the rival counting as the wrong item.
    package static func candidates(_ slots: [Slot], by feature: Feature) -> [WordDoubtEvaluation.Scored] {
        let forcedSpread = spread(slots.flatMap { [$0.forcedDifference, -$0.forcedDifference] })
        let marginSpread = spread(slots.flatMap { [$0.meantMargin, $0.otherMargin] })
        return slots.flatMap { slot -> [WordDoubtEvaluation.Scored] in
            let meant: Double
            let other: Double
            switch feature {
            case .forced:
                (meant, other) = (slot.forcedDifference, -slot.forcedDifference)
            case .greedyMargin:
                (meant, other) = (slot.meantMargin, slot.otherMargin)
            case .both:
                meant = slot.forcedDifference / forcedSpread + slot.meantMargin / marginSpread
                other = -slot.forcedDifference / forcedSpread + slot.otherMargin / marginSpread
            }
            return [
                WordDoubtEvaluation.Scored(certainty: meant, isWrong: false, cluster: slot.cluster),
                WordDoubtEvaluation.Scored(certainty: other, isWrong: true, cluster: slot.cluster),
            ]
        }
    }

    /// AUROC of `feature`, with a 95% interval from resampling whole clusters.
    package static func auroc(_ slots: [Slot], by feature: Feature) -> WordDoubtEvaluation.Interval? {
        WordDoubtEvaluation.resampled(slots, by: \.cluster) {
            WordDoubtEvaluation.auroc(candidates($0, by: feature))
        }
    }

    /// AUROC of `feature` minus that of `baseline`, both read on the same resampled clusters.
    package static func advantage(
        of feature: Feature, over baseline: Feature, in slots: [Slot]
    ) -> WordDoubtEvaluation.Interval? {
        WordDoubtEvaluation.resampled(slots, by: \.cluster) { sample in
            guard let gained = WordDoubtEvaluation.auroc(candidates(sample, by: feature)),
                let base = WordDoubtEvaluation.auroc(candidates(sample, by: baseline))
            else { return nil }
            return gained - base
        }
    }

    /// Slots where the forced score prefers the rival and the greedy step chose the rival too.
    package static func confidentErrors(_ slots: [Slot]) -> Int {
        slots.count { $0.forcedDifference <= 0 && $0.otherMargin > 0 }
    }

    /// The AUROC table, the forced-minus-margin difference and the confident errors, as the probe prints them.
    package static func markdown(_ slots: [Slot]) -> String {
        let clusters = Set(slots.map(\.cluster)).count
        let difference = cells(advantage(of: .forced, over: .greedyMargin, in: slots), format: "%+.3f")
        var lines = [
            "slots \(slots.count) in \(clusters) clusters; 95% intervals resample whole clusters",
            "",
            "| Feature | AUROC | 95% interval |",
            "|---|---|---|",
        ]
        for feature in Feature.allCases {
            let measured = cells(auroc(slots, by: feature), format: "%.3f")
            lines.append("| \(feature.rawValue) | \(measured.value) | \(measured.range) |")
        }
        lines += [
            "",
            "forced minus greedy-step margin: \(difference.value), 95% interval \(difference.range)",
            "confident errors (forced and greedy step both prefer the rival): \(confidentErrors(slots))",
        ]
        return lines.joined(separator: "\n")
    }

    private static func cells(
        _ interval: WordDoubtEvaluation.Interval?, format: String
    ) -> (value: String, range: String) {
        guard let interval else { return ("-", "-") }
        return (
            String(format: format, interval.value),
            String(format: "[\(format), \(format)]", interval.low, interval.high)
        )
    }

    /// Standard deviation of `values`; 1 when they do not vary, so dividing by it leaves them as they are.
    private static func spread(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 1 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
        return variance > 0 ? variance.squareRoot() : 1
    }
}
