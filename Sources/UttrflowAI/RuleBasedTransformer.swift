public import UttrflowCore

/// The floor beneath every other transformer: the deterministic passes alone, which cannot invent or refuse.
public struct RuleBasedTransformer: TextTransformationEngine {
    public let kind: TransformerKind = .rules

    private let pipeline: CleaningPipeline?
    private let steps: CleaningSteps

    /// A pipeline given here runs as it is; none means the standard one for each request's place and caret.
    public init(pipeline: CleaningPipeline? = nil, steps: CleaningSteps = .default) {
        self.pipeline = pipeline
        self.steps = steps
    }

    /// Always available, in any language, because it only rearranges what is already there.
    public func availability(for request: TransformationRequest) async -> TransformerAvailability {
        .available
    }

    public func transform(
        _ request: TransformationRequest
    ) async throws(TransformationError) -> TransformationResult {
        let formatter = DestinationFormatter.standard(for: request.situation.destination)
        let pipeline =
            pipeline ?? .standard(for: formatter, situation: request.situation, steps: steps)
        let draft = pipeline.run(Draft(transcription: request.transcription))
        return TransformationResult(
            text: draft.text, producedBy: kind,
            cleaning: CleaningRecord(draft: draft, ran: pipeline.ids))
    }
}
