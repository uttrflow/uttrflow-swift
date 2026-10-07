// Scores how well each candidate reading fits the words around it, and speaks only when one clearly fits best.

import Foundation
public import UttrflowCore

/// Several n-gram models mixed by linear interpolation of their probabilities, such as a user model and a technical one.
public struct InterpolatedLanguageModel: Sendable {
    /// One model and the share of probability it contributes.
    public struct Component: Sendable {
        /// The model mixed in.
        public let model: NGramModel
        /// Its share before the shares are scaled to sum to 1.
        public let weight: Float

        public init(model: NGramModel, weight: Float) {
            self.model = model
            self.weight = weight
        }
    }

    private let components: [Component]

    /// Mixes `components`, scaling their positive weights to sum to 1 and dropping any without weight.
    public init(_ components: [Component]) {
        let kept = components.filter { $0.weight > 0 && $0.weight.isFinite }
        let total = kept.reduce(Float(0)) { $0 + $1.weight }
        self.components = kept.map { Component(model: $0.model, weight: $0.weight / total) }
    }

    /// The highest order among the mixed models.
    public var order: Int { components.map(\.model.order).max() ?? 1 }

    /// The log10 of the weighted sum of each model's probability for `word` after `history`.
    public func log10Probability(of word: String, after history: [String]) -> Float {
        let mixed = components.reduce(Float(0)) { sum, part in
            sum + part.weight * pow10(part.model.log10Probability(of: word, after: history))
        }
        return mixed > 0 ? log10f(mixed) : NGramModel.unseenLog10Probability
    }

    /// The summed log10 probability of `span` after `left`, then of each word of `right` after it.
    public func log10Probability(ofSpan span: [String], between left: [String], and right: [String]) -> Float
    {
        var context = Array(left.suffix(max(order - 1, 0)))
        var total: Float = 0
        for word in span + right.prefix(max(order - 1, 0)) {
            total += log10Probability(of: word, after: context)
            context.append(word)
            if context.count >= order { context.removeFirst() }
        }
        return total
    }

    private func pow10(_ exponent: Float) -> Float { powf(10, exponent) }
}

/// What the context says about a set of candidate readings for one span.
public enum ContextVerdict: Sendable, Equatable {
    /// The context does not separate the candidates by the margin, so other evidence decides.
    case undecided
    /// The candidate at this index fits the context better than every other by at least the margin.
    case prefers(Int)
}

/// Compares candidate readings of one span by how well they fit the surrounding words; a veto and tie-breaker, never the sole judge.
public struct ContextScorer: Sendable {
    /// The log10 lead a candidate needs over every other before the scorer prefers it.
    public static let defaultMargin: Float = 1
    private let model: InterpolatedLanguageModel
    private let margin: Float

    public init(model: InterpolatedLanguageModel, margin: Float = ContextScorer.defaultMargin) {
        self.model = model
        self.margin = margin
    }

    /// The candidate the context prefers by at least the margin, or `.undecided` when none leads by that much.
    public func verdict(
        on candidates: [[String]], between left: [String], and right: [String]
    ) -> ContextVerdict {
        let scores = candidates.map { model.log10Probability(ofSpan: $0, between: left, and: right) }
        guard let best = scores.indices.max(by: { scores[$0] < scores[$1] }) else { return .undecided }
        let runnerUp = scores.indices.filter { $0 != best }.map { scores[$0] }.max()
        guard let runnerUp else { return .undecided }
        return scores[best] - runnerUp >= margin ? .prefers(best) : .undecided
    }
}
