// What a calibrated value was fitted on and under, so a layer moving beneath it cannot leave it stale.

/// One calibrated value with the corpus, metric and layer revisions it was fitted under.
public struct CalibrationRecord: Sendable, Equatable {
    /// A layer of the recognition chain, numbered in the one order the chain is fitted in.
    public enum Layer: Int, Sendable, Comparable, CaseIterable {
        /// The recogniser's pinned weights.
        case recogniser = 0
        /// The log-odds the decode-time phrase bias adds.
        case phraseBias = 1
        /// The conditioning prompt's wording and token budgets.
        case conditioningPrompt = 2
        /// The temperature retries and log-probability test a rejected window gets.
        case fallbackPlan = 3
        /// The score under which a heard word is doubted.
        case certaintyThreshold = 4
        /// The evidence an override must win by.
        case overrideMargin = 5

        public static func < (lhs: Layer, rhs: Layer) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// The layer this value calibrates.
    public let layer: Layer
    /// The value as its owner writes it, so a changed constant is a changed record.
    public let value: String
    /// What the value was fitted or chosen on.
    public let corpus: String
    /// What the fit optimised or held.
    public let metric: String
    /// The revision of every earlier layer the value reads, as it was when the value was fitted.
    public let fittedUnder: [Layer: String]

    public init(
        layer: Layer, value: String, corpus: String, metric: String, fittedUnder: [Layer: String]
    ) {
        self.layer = layer
        self.value = value
        self.corpus = corpus
        self.metric = metric
        self.fittedUnder = fittedUnder
    }
}
