// The one reason a dictation waits past its target, named from where its time goes beyond the usual.

/// Why a dictation's wait after key-up runs past the target, from a closed list so counts can be compared.
public enum SlowDictationCause: String, Sendable, Equatable, CaseIterable, Codable {
    /// Loading or compiling the speech model for this dictation.
    case modelLoad
    /// Decoding a window again at a higher temperature.
    case fallbackDecode
    /// Decoding a piece again after a decode stops at the token cap or returns nothing.
    case cappedDecodeRetry
    /// The tidier running out of time, so its answer is dropped.
    case tidyTimeout
    /// Starting the tidier's session cold for this dictation.
    case tidyColdSession
    /// Reading the focused field and its surroundings.
    case contextRead
    /// Placing the text and confirming it reaches the field.
    case insertionConfirmation
    /// Time that no named cause accounts for.
    case other

    /// The cause furthest past its `typical` cost once `wait` exceeds `target`; `other` when none is.
    public static func of(
        wait: Duration, target: Duration,
        spent: [SlowDictationCause: Duration], typical: [SlowDictationCause: Duration]
    ) -> SlowDictationCause? {
        guard wait > target else { return nil }
        let excess = allCases.map { cause in
            (cause, (spent[cause] ?? .zero) - (typical[cause] ?? .zero))
        }
        guard let worst = excess.max(by: { $0.1 < $1.1 }), worst.1 > .zero else { return .other }
        return worst.0
    }
}
