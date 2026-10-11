// The decoder's evidence for one token of a recognised word, carried for measuring word-level doubt.

/// The decoder's evidence for one token of a word: the chosen token and the runners-up at that step.
package struct TokenEvidence: Sendable, Equatable {
    /// Log-probability of the token the decoder chose.
    package let logProb: Double
    /// Log-probabilities of the other leading tokens at the same step, any order.
    package let alternatives: [Double]

    /// Evidence for one token.
    package init(logProb: Double, alternatives: [Double] = []) {
        self.logProb = logProb
        self.alternatives = alternatives
    }
}
