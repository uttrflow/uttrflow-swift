// What a piece is decoded and tidied after, made in one place for every path. See `Docs/early-transcription.md`.

/// The previous piece's words as corrected and not yet tidied, which every path has once a piece is corrected.
struct RollingContext: Sendable, Equatable {
    let text: String

    /// The context the next piece reads after these words, or `nil` when they said nothing.
    init?(after corrected: CorrectedTranscript) {
        guard corrected.text.contains(where: { !$0.isWhitespace }) else { return nil }
        text = corrected.text
    }
}
