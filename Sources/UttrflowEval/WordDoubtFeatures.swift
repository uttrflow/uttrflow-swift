// Candidate word-level doubt features built from per-token evidence, and how well each predicts a wrong word.
import Foundation

/// The decoder's evidence for one token of a word: the chosen token and the runners-up at that step.
public struct TokenEvidence: Sendable, Equatable {
    /// Log-probability of the token the decoder chose.
    public let logProb: Double
    /// Log-probabilities of the other leading tokens at the same step, any order.
    public let alternatives: [Double]

    /// Evidence for one token.
    public init(logProb: Double, alternatives: [Double] = []) {
        self.logProb = logProb
        self.alternatives = alternatives
    }
}

/// One way of turning a word's token evidence into a single certainty; lower means more doubtful.
public enum WordDoubtFeature: String, CaseIterable, Sendable {
    /// Exp of the mean token log-probability: the score the pipeline uses today, unrounded.
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
    public func certainty(of tokens: [TokenEvidence]) -> Double? {
        guard let first = tokens.first else { return nil }
        switch self {
        case .mean:
            return exp(tokens.map(\.logProb).reduce(0, +) / Double(tokens.count))
        case .minimum:
            return tokens.map { exp($0.logProb) }.min()
        case .firstToken:
            return exp(first.logProb)
        case .firstMargin:
            return exp(first.logProb) - (first.alternatives.max().map(exp) ?? 0)
        case .negatedEntropy:
            return -tokens.map(Self.entropy).reduce(0, +) / Double(tokens.count)
        }
    }

    private static func entropy(_ token: TokenEvidence) -> Double {
        let probabilities = ([token.logProb] + token.alternatives).map(exp)
        let total = probabilities.reduce(0, +)
        return -probabilities.map { $0 / total }.filter { $0 > 0 }.map { $0 * log($0) }.reduce(0, +)
    }
}

/// How well a certainty separates wrong words from right ones.
public enum WordDoubtEvaluation {
    /// One scored word: its certainty, whether it differs from the reference, and the cluster it was read in.
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
        var flagged = 0
        var flaggedWrong = 0
        var best = 0
        for word in words.sorted(by: { $0.certainty < $1.certainty }) {
            flagged += 1
            if word.isWrong { flaggedWrong += 1 }
            if Double(flaggedWrong) >= precision * Double(flagged) { best = flaggedWrong }
        }
        return Double(best) / Double(wrong)
    }

    /// `statistic` with a percentile interval from resampling whole clusters, so one voice cannot narrow it.
    public static func clustered(
        _ words: [Scored], resamples: Int = 1000, seed: UInt64 = 1, _ statistic: ([Scored]) -> Double?
    ) -> Interval? {
        guard let value = statistic(words) else { return nil }
        let clusters = Dictionary(grouping: words, by: \.cluster).values.map(Array.init)
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
