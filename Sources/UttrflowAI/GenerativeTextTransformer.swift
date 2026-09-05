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
    private let prompts: PromptBuilder
    private let meaningGuard: MeaningPreservationGuard
    private let pipeline: CleaningPipeline

    /// `pipeline` runs before the model and should leave casing and the full stop for afterwards.
    public init(
        kind: TransformerKind,
        model: any CleanupModel,
        prompts: PromptBuilder = .standard,
        meaningGuard: MeaningPreservationGuard = MeaningPreservationGuard(),
        pipeline: CleaningPipeline = .beforeModel
    ) {
        self.kind = kind
        self.model = model
        self.prompts = prompts
        self.meaningGuard = meaningGuard
        self.pipeline = pipeline
    }

    public func availability(for request: TransformationRequest) async -> TransformerAvailability {
        await model.availability(for: request.effectiveLanguage)
    }

    /// Hands the model the instructions for where the words are going, plain text's when that is not known.
    public func warm(for situation: Situation?) async {
        await model.warm(instructions: prompts.instructions(for: situation?.destination ?? .plain))
    }

    public func transform(
        _ request: TransformationRequest
    ) async throws(TransformationError) -> TransformationResult {
        // The passes go first, so fillers and self-corrections are gone before the model can rewrite them.
        let draft = pipeline.run(Draft(transcription: request.transcription))
        let spoken = draft.text
        let rewritten = try await model.rewrite(
            prompts.userPrompt(for: request, spoken: spoken),
            instructions: prompts.instructions(for: request.situation.destination), kind: kind
        )

        // Models echo the shape of the worked examples, so the answer is unwrapped before it is judged.
        let unwrapped = ResponseUnwrapper.unwrap(rewritten, spoken: spoken)
        let formatter = DestinationFormatter.standard(for: request.situation.destination)
        let finishing = CleaningPipeline.afterModel(
            for: formatter, situation: request.situation, heard: request.transcription.text)
        let finished = finishing.run(Draft(keepingLineBreaks: TextTidy.collapseSpacing(unwrapped))).text

        // A refusal is not a failure: the router moves on, and the floor beneath it cannot invent anything.
        if case .rejected(let reason) = meaningGuard.verdict(draft: draft, rewritten: finished) {
            throw .outputRejected(reason: reason)
        }

        return TransformationResult(text: finished, producedBy: kind)
    }
}
