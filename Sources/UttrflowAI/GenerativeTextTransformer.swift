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
    private let pipeline: CleaningPipeline

    /// `pipeline` runs before the model and should leave casing and the full stop for afterwards.
    public init(
        kind: TransformerKind,
        model: any CleanupModel,
        prompt: CleanupPrompt = .current,
        meaningGuard: MeaningPreservationGuard = MeaningPreservationGuard(),
        pipeline: CleaningPipeline = .beforeModel
    ) {
        self.kind = kind
        self.model = model
        self.prompt = prompt
        self.meaningGuard = meaningGuard
        self.pipeline = pipeline
    }

    public func availability(for request: TransformationRequest) async -> TransformerAvailability {
        await model.availability(for: request.effectiveLanguage)
    }

    /// Hands the model the instructions every request carries, ahead of the request.
    public func warm() async {
        await model.warm(instructions: prompt.instructions)
    }

    public func transform(
        _ request: TransformationRequest
    ) async throws(TransformationError) -> TransformationResult {
        // The passes go first, so fillers and self-corrections are gone before the model can rewrite them.
        let draft = pipeline.run(Draft(transcription: request.transcription))
        let spoken = draft.text
        let rewritten = try await model.rewrite(
            prompt.userPrompt(for: request, spoken: spoken), instructions: prompt.instructions, kind: kind
        )

        // Models echo the shape of the worked examples, so the answer is unwrapped before it is judged.
        let unwrapped = ResponseUnwrapper.unwrap(rewritten, spoken: spoken)
        let finished = TextTidy.ensureTerminalPunctuation(TextTidy.collapseSpacing(unwrapped))

        // A refusal is not a failure: the router moves on, and the floor beneath it cannot invent anything.
        if case .rejected(let reason) = meaningGuard.verdict(draft: draft, rewritten: finished) {
            throw .outputRejected(reason: reason)
        }

        return TransformationResult(text: finished, producedBy: kind)
    }
}
