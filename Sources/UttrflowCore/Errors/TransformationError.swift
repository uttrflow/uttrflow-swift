/// A failure while cleaning up a transcript; rare, as the preference list ends in a transformer for anything.
public enum TransformationError: UttrflowFailure {
    /// Every transformer in the preference list declined the request.
    case noCapableTransformer
    /// The named transformer ran and failed, for the class of reason given.
    case transformFailed(kind: TransformerKind, failure: ModelFailureClass)
    /// The model returned something that failed the meaning-preservation checks.
    case outputRejected(reason: String, kind: RefusalKind)
    /// The caller cancelled the route before an engine answered.
    case cancelled

    /// The one sentence: the raw words are ready to paste.
    public var userMessage: String {
        switch self {
        case .noCapableTransformer, .transformFailed, .outputRejected, .cancelled:
            "Your words were captured, but couldn't be tidied up. The raw text is copied, so press ⌘V to paste it."
        }
    }

    /// Paste the raw words, which are on the clipboard.
    public var recovery: RecoveryAction? { .pasteManually }

    /// Degraded: clean-up is the only optional stage, so failing it costs polish and never output.
    public var severity: FailureSeverity { .degraded }
}
