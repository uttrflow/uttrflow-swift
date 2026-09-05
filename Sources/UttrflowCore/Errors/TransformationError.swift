/// A failure while cleaning up a transcript; rare, as the preference list ends in a transformer for anything.
public enum TransformationError: UttrflowFailure {
    /// Every transformer in the preference list declined the request.
    case noCapableTransformer
    /// The named transformer ran and failed.
    case transformFailed(kind: TransformerKind, description: String)
    /// The model returned something that failed the meaning-preservation checks.
    case outputRejected(reason: String)

    /// The one sentence: the raw words are ready to paste.
    public var userMessage: String {
        switch self {
        case .noCapableTransformer, .transformFailed, .outputRejected:
            "Your words were captured, but couldn't be tidied up. The raw text is ready to paste."
        }
    }

    /// Paste the raw words, which are on the clipboard.
    public var recovery: RecoveryAction? { .pasteManually }

    /// Degraded: clean-up is the only optional stage, so failing it costs polish and never output.
    public var severity: FailureSeverity { .degraded }
}
