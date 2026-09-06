public import UttrflowCore

/// Cleans a transcript with any ``CleanupModel`` and refuses a rewrite that changes what the speaker meant.
public struct GenerativeTextTransformer: TextTransformationEngine {
    /// Which engine this stands for.
    public let kind: TransformerKind

    /// The model that rewrites.
    private let model: any CleanupModel
    /// The instructions and the wrapping every request gets.
    private let prompt: CleanupPrompt
    /// Rejects a rewrite that changed the meaning.
    private let meaningGuard: MeaningPreservationGuard

    /// Pairs a model with a prompt and a guard; the defaults are the shipping ones.
    public init(
        kind: TransformerKind,
        model: any CleanupModel,
        prompt: CleanupPrompt = .current,
        meaningGuard: MeaningPreservationGuard = MeaningPreservationGuard()
    ) {
        self.kind = kind
        self.model = model
        self.prompt = prompt
        self.meaningGuard = meaningGuard
    }

    /// Passes the model's own verdict on the spoken language straight through.
    public func availability(for request: TransformationRequest) async -> TransformerAvailability {
        await model.availability(for: request.effectiveLanguage)
    }

    /// Hands the model the instructions every request carries, ahead of the request.
    public func warm() async {
        await model.warm(instructions: prompt.instructions)
    }

    /// Rewrites, unwraps and tidies, then throws `outputRejected` when the meaning guard refuses.
    public func transform(
        _ request: TransformationRequest
    ) async throws(TransformationError) -> TransformationResult {
        let spoken = request.transcription.text
        let rewritten = try await model.rewrite(
            prompt.userPrompt(for: request), instructions: prompt.instructions, kind: kind
        )

        // Models echo the worked examples' label around the answer, so it is unwrapped before judging.
        let unwrapped = ResponseUnwrapper.unwrap(rewritten, spoken: spoken)
        let formatter = DestinationFormatter.standard(for: request.situation.destination)
        let cased = FirstWordRule.apply(
            TextTidy.collapseSpacing(unwrapped), heard: spoken, policy: formatter.firstWord,
            state: request.situation.insertion.sentenceState, onScreen: request.situation.app.textOnScreen)
        let finished = TerminalStopRule.apply(cased, policy: formatter.terminalStop)

        // A rejection is not a product failure: the router moves on to the next engine.
        if case .rejected(let reason) = meaningGuard.verdict(original: spoken, rewritten: finished) {
            throw .outputRejected(reason: reason)
        }

        return TransformationResult(text: finished, producedBy: kind)
    }
}
