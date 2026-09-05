public import UttrflowCore

/// The floor beneath every other transformer.
///
/// Deterministic, instant, and incapable of inventing anything, so it can never
/// decline a request. Everything above it may fail or refuse; this cannot, which is
/// what makes the pipeline unable to dead-end.
public struct RuleBasedTransformer: TextTransformationEngine {
    public let kind: TransformerKind = .rules

    public init() {}

    /// Always available. It works on any language, because it only rearranges what is
    /// already there.
    public func availability(for request: TransformationRequest) async -> TransformerAvailability {
        .available
    }

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
