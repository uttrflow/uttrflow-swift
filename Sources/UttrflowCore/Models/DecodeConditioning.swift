// Whether the recogniser could condition a decode on the user's words, and why not when it could not.

/// Whether a piece was decoded with the help that needs a tokenizer: the vocabulary prompt and its decode-time rules.
public enum DecodeConditioning: Sendable, Equatable {
    /// The recogniser had what it needs to prompt and bias the decode.
    case available
    /// The decode ran unbiased because something it needs was missing.
    case unavailable(Reason)

    /// Why a decode ran without conditioning.
    public enum Reason: String, Sendable, Equatable {
        /// The recogniser loaded without a usable tokenizer.
        case tokenizerUnavailable
    }

    /// Unavailable wins, so one degraded window marks the whole piece.
    public func adding(_ other: DecodeConditioning) -> DecodeConditioning {
        if case .unavailable = self { return self }
        return other
    }
}
