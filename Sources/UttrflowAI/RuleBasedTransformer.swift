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
        let formatter = DestinationFormatter.standard(for: request.situation.destination)
        var text = TextTidy.collapseWhitespace(request.transcription.text)
        text = TextTidy.removeFillers(text)
        text = TextTidy.capitalisePronounI(text)
        text = TextTidy.capitaliseSentences(text)
        text = FirstWordRule.apply(
            text, heard: request.transcription.text, policy: formatter.firstWord,
            state: request.situation.insertion.sentenceState, onScreen: request.situation.app.textOnScreen)
        text = TerminalStopRule.apply(text, policy: formatter.terminalStop)
        return TransformationResult(text: text, producedBy: kind)
    }
}
