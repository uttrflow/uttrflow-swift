// Candidate word-level doubt features built from per-token evidence, and how well each predicts a wrong word.
import Foundation
package import UttrflowCore

/// One way of turning a word's token evidence into a single certainty; lower means more doubtful.
public enum WordDoubtFeature: String, CaseIterable, Sendable {
    /// Exp of the mean token log-probability, unrounded: the scale the doubt gate reads today.
    case mean
    /// The least probable token.
    case minimum
    /// The first token's probability.
    case firstToken
    /// The first token's probability minus its strongest runner-up's.
    case firstMargin
    /// Negated mean entropy of the leading tokens, renormalised, over the word's tokens.
    case negatedEntropy

    /// This feature's certainty for a word; nil when the word has no tokens.
    package func certainty(of tokens: [TokenEvidence]) -> Double? {
        guard let first = tokens.first else { return nil }
        switch self {
        case .mean:
            return DecoderCertainty(tokens: tokens)?.meanProbability
        case .minimum:
            return tokens.map { exp($0.logProb) }.min()
        case .firstToken:
            return exp(first.logProb)
        case .firstMargin:
            return exp(first.logProb) - (first.alternatives.max().map(exp) ?? 0)
        case .negatedEntropy:
            return DecoderCertainty(tokens: tokens)?.negatedEntropy
        }
    }
}

/// How well a certainty separates wrong words from right ones.
public enum WordDoubtEvaluation {
    /// One scored word: its certainty, whether it differs from the reference, and the cluster it is read in.
    public struct Scored: Sendable, Equatable {
        public let certainty: Double
        public let isWrong: Bool
        public let cluster: String

        public init(certainty: Double, isWrong: Bool, cluster: String) {
            self.certainty = certainty
            self.isWrong = isWrong
            self.cluster = cluster
        }
    }

    /// A point estimate with a 95% interval.
    public struct Interval: Sendable, Equatable {
        public let value: Double
        public let low: Double
        public let high: Double
    }

    /// Chance a wrong word scores below a right one; nil without both kinds.
    public static func auroc(_ words: [Scored]) -> Double? {
        HomophoneConfidence.auc(
            wrong: words.filter(\.isWrong).map(\.certainty),
            right: words.filter { !$0.isWrong }.map(\.certainty))
    }

    /// Share of wrong words flagged at the highest threshold whose flags are at least `precision` wrong; 0 when none is.
    public static func recall(_ words: [Scored], atPrecision precision: Double) -> Double {
        let wrong = words.count(where: \.isWrong)
        guard wrong > 0 else { return 0 }
        return Double(widestFlag(words, atPrecision: precision)?.caught ?? 0) / Double(wrong)
    }

    /// The certainty at or below which words are flagged by that highest threshold; nil when no flag reaches `precision`.
    package static func threshold(_ words: [Scored], atPrecision precision: Double) -> Double? {
        widestFlag(words, atPrecision: precision)?.threshold
    }

    /// The longest run of lowest-scored words whose flags are at least `precision` wrong: its last certainty and the wrong words in it.
    private static func widestFlag(
        _ words: [Scored], atPrecision precision: Double
    ) -> (threshold: Double, caught: Int)? {
        var flagged = 0
        var flaggedWrong = 0
        var best: (threshold: Double, caught: Int)?
        for word in words.sorted(by: { $0.certainty < $1.certainty }) {
            flagged += 1
            if word.isWrong { flaggedWrong += 1 }
            if flaggedWrong > 0, Double(flaggedWrong) >= precision * Double(flagged) {
                best = (word.certainty, flaggedWrong)
            }
        }
        return best
    }

    /// `statistic` with a percentile interval from resampling whole clusters, so one voice cannot narrow it.
    public static func clustered(
        _ words: [Scored], resamples: Int = 1000, seed: UInt64 = 1, _ statistic: ([Scored]) -> Double?
    ) -> Interval? {
        resampled(words, by: \.cluster, resamples: resamples, seed: seed, statistic)
    }

    /// `statistic` with a percentile interval from resampling whole clusters of any measured item.
    package static func resampled<Sample>(
        _ words: [Sample], by cluster: (Sample) -> String, resamples: Int = 1000, seed: UInt64 = 1,
        _ statistic: ([Sample]) -> Double?
    ) -> Interval? {
        guard let value = statistic(words) else { return nil }
        let clusters = Dictionary(grouping: words, by: cluster).values.map(Array.init)
        var generator = SplitMix(state: seed)
        var draws: [Double] = []
        for _ in 0..<resamples {
            let sample = (0..<clusters.count).flatMap { _ in
                clusters[Int(generator.next() % UInt64(clusters.count))]
            }
            if let draw = statistic(sample) { draws.append(draw) }
        }
        draws.sort()
        guard !draws.isEmpty else { return Interval(value: value, low: value, high: value) }
        let low = draws[Int(Double(draws.count - 1) * 0.025)]
        let high = draws[Int(Double(draws.count - 1) * 0.975)]
        return Interval(value: value, low: low, high: high)
    }

    private struct SplitMix {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var mixed = state
            mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
            mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
            return mixed ^ (mixed >> 31)
        }
    }
}

/// Marks each recognised word right or wrong against the words that were read.
package enum WordDoubtAlignment {
    /// For each of `heard`, whether a minimum-edit alignment with `reference` matches it to the same word.
    package static func wrong(reference: [String], heard: [String]) -> [Bool] {
        zip(heard, read(reference: reference, heard: heard)).map { $0 != $1 }
    }

    /// For each of `heard`, the read word a minimum-edit alignment pairs it with; nil for a word that was never read.
    package static func read(reference: [String], heard: [String]) -> [String?] {
        let rows = reference.count
        let columns = heard.count
        var cost = Array(repeating: Array(repeating: 0, count: columns + 1), count: rows + 1)
        for row in 0...rows { cost[row][0] = row }
        for column in 0...columns { cost[0][column] = column }
        for row in stride(from: 1, through: rows, by: 1) {
            for column in stride(from: 1, through: columns, by: 1) {
                let match = reference[row - 1] == heard[column - 1] ? 0 : 1
                cost[row][column] = min(
                    cost[row - 1][column - 1] + match, cost[row - 1][column] + 1, cost[row][column - 1] + 1)
            }
        }
        var paired = [String?](repeating: nil, count: columns)
        var row = rows
        var column = columns
        while row > 0, column > 0 {
            let match = reference[row - 1] == heard[column - 1] ? 0 : 1
            if cost[row][column] == cost[row - 1][column - 1] + match {
                paired[column - 1] = reference[row - 1]
                row -= 1
                column -= 1
            } else if cost[row][column] == cost[row][column - 1] + 1 {
                column -= 1
            } else {
                row -= 1
            }
        }
        return paired
    }
}
