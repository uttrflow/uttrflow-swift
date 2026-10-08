// The one answer to what a layer does when a draft's word scores are stand-ins rather than evidence.
public import UttrflowCore

/// What each consumer of word confidence does when the recogniser gave no real scores. See Docs/unknown-confidence.md.
public enum EvidencePolicy {
    /// A layer that reads word confidence.
    public enum Layer: CaseIterable, Sendable {
        case doubtfulWords, meaningGuard, rulesAlone, dictionarySpellings, explanation
    }

    /// What a layer does in place of reading a stand-in score.
    public enum Unscored: Equatable, Sendable {
        /// Offers no doubtful span: with no doubt signal no span is evidence.
        case offerNothing
        /// Accepts the rewrite: no word was shown to be sure, so none is protected.
        case acceptRewrite
        /// Sends the text to the model: unknown cannot rule doubt out.
        case askModel
        /// Rewrites the text and carries no word scores forward.
        case dropScores
        /// Says the words were not scored rather than printing a stand-in as certainty.
        case sayNotScored
    }

    /// The layer's choice when `draft` has no real scores, or `nil` when its scores are evidence and the layer reads them.
    public static func unscored(_ draft: Draft, in layer: Layer) -> Unscored? {
        draft.confidencesAreReal ? nil : choice(for: layer)
    }

    /// Each layer's standing choice for unknown confidence; a change is made only on measured grounds.
    public static func choice(for layer: Layer) -> Unscored {
        switch layer {
        case .doubtfulWords: .offerNothing
        case .meaningGuard: .acceptRewrite
        case .rulesAlone: .askModel
        case .dictionarySpellings: .dropScores
        case .explanation: .sayNotScored
        }
    }
}
