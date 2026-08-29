/// A failure while cleaning up a transcript.
///
/// These should be rare: the preference list always ends in a transformer that can
/// handle anything, so reaching one of these means the floor itself failed.
public enum TransformationError: UttrflowFailure {
    /// Every transformer in the preference list declined the request.
    case noCapableTransformer
    case transformFailed(kind: TransformerKind, description: String)
    /// The model returned something that failed the meaning-preservation checks.
    case outputRejected(reason: String)

    public var userMessage: String {
        switch self {
        case .noCapableTransformer, .transformFailed, .outputRejected:
            "Your words were captured, but couldn't be tidied up. The raw text is ready to paste."
        }
    }

    public var recovery: RecoveryAction? { .pasteManually }

    /// Clean-up is the only optional stage, so failing it costs polish and never
    /// output: the raw words are captured, tidied or not.
    public var severity: FailureSeverity { .degraded }
}
