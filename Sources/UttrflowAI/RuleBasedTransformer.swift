public import UttrflowCore

/// The floor beneath every other transformer: deterministic, instant, and unable to decline or invent.
public struct RuleBasedTransformer: TextTransformationEngine {
    /// Always `.rules`.
    public let kind: TransformerKind = .rules

    /// Makes the floor; it holds no state.
    public init() {}

    /// Always available, in any language, because it only rearranges what is already there.
    public func availability(for request: TransformationRequest) async -> TransformerAvailability {
        .available
    }

    /// Collapses whitespace, drops fillers, capitalises, and finishes the sentence.
    public func transform(
        _ request: TransformationRequest
    ) async throws(TransformationError) -> TransformationResult {
        var text = TextTidy.collapseWhitespace(request.transcription.text)
        text = TextTidy.removeFillers(text)
        text = TextTidy.capitalisePronounI(text)
        text = TextTidy.capitaliseSentences(text)
        text = TextTidy.ensureTerminalPunctuation(text)
        return TransformationResult(text: text, producedBy: kind)
    }
}
