public import UttrflowCore

/// Cleans a transcript using a language model, and refuses to pass on a rewrite that
/// changed what the speaker meant.
///
/// One implementation serves every generative engine — Apple's on-device model today,
/// a local open-weight model and a hosted one later — because the difference between
/// them is which ``CleanupModel`` is handed in, and nothing else.
public struct GenerativeTextTransformer: TextTransformationEngine {
    public let kind: TransformerKind

    private let model: any CleanupModel
    private let prompt: CleanupPrompt
    private let meaningGuard: MeaningPreservationGuard

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

    public func availability(for request: TransformationRequest) async -> TransformerAvailability {
        await model.availability(for: request.effectiveLanguage)
    }

    public func transform(
        _ request: TransformationRequest
    ) async throws(TransformationError) -> TransformationResult {
        let spoken = request.transcription.text
        let rewritten = try await model.rewrite(
            prompt.userPrompt(for: request), instructions: prompt.instructions, kind: kind
        )

        // Models echo the shape of the worked examples, so the answer often arrives
        // wrapped in the label they were shown. Unwrap before judging it.
        let unwrapped = ResponseUnwrapper.unwrap(rewritten, spoken: spoken)
        let finished = TextTidy.ensureTerminalPunctuation(TextTidy.collapseSpacing(unwrapped))

        // Rejecting is not a failure of the product: the router simply moves to the
        // next engine, and the floor beneath them all cannot invent anything.
        if case .rejected(let reason) = meaningGuard.verdict(original: spoken, rewritten: finished) {
            throw .outputRejected(reason: reason)
        }

        return TransformationResult(text: finished, producedBy: kind)
    }
}
