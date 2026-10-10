// A recognised word's certainty, typed by where it came from so two engines' scores never meet unconverted.
import Foundation

/// The decoder's certainty for one word, computed from its own tokens and never rounded.
public struct DecoderCertainty: Sendable, Equatable {
    /// Exp of the mean token log-probability, 0 to 1.
    public let meanProbability: Double
    /// Minus the mean entropy of each token's leading choices; the chosen doubt feature, see Docs/decoder-evidence.md.
    public let negatedEntropy: Double

    /// The certainty of a word with these tokens; nil when it has none.
    package init?(tokens: [TokenEvidence]) {
        guard !tokens.isEmpty else { return nil }
        let count = Double(tokens.count)
        meanProbability = exp(tokens.map(\.logProb).reduce(0, +) / count)
        negatedEntropy = -tokens.map(Self.entropy).reduce(0, +) / count
    }

    private static func entropy(_ token: TokenEvidence) -> Double {
        let probabilities = ([token.logProb] + token.alternatives).map(exp)
        let total = probabilities.reduce(0, +)
        return -probabilities.map { $0 / total }.filter { $0 > 0 }.map { $0 * log($0) }.reduce(0, +)
    }
}

/// A whole-word probability an engine reported with no token evidence behind it, 0 to 1.
public struct ReportedCertainty: Sendable, Equatable {
    /// The engine's own value.
    public let probability: Double

    /// The value as the engine reported it.
    public init(probability: Double) {
        self.probability = probability
    }
}

/// How sure the recogniser is of a word, carrying which kind of score it is.
public enum WordCertainty: Sendable, Equatable {
    /// Computed here from the decoder's token evidence.
    case decoder(DecoderCertainty)
    /// Reported by the engine for the whole word.
    case reported(ReportedCertainty)

    /// The explicit conversion to the 0-to-1 scale `DoubtPolicy.certaintyThreshold` is set on.
    public var gateConfidence: Double {
        switch self {
        case .decoder(let certainty): certainty.meanProbability
        case .reported(let certainty): certainty.probability
        }
    }
}
