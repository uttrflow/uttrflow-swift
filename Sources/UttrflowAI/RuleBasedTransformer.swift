public import UttrflowCore

/// The floor beneath every other transformer: the deterministic passes alone, which cannot invent or refuse.
public struct RuleBasedTransformer: TextTransformationEngine {
    /// Always `.rules`.
    public let kind: TransformerKind = .rules

    /// Three orders of magnitude more than it needs: this engine only rearranges words already in hand.
    public let budget: Duration = StageTimeout.rules

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

    /// Romanises Devanagari, collapses whitespace, drops fillers, capitalises, and finishes the sentence.
    public func transform(
        _ request: TransformationRequest
    ) async throws(TransformationError) -> TransformationResult {
        let formatter = DestinationFormatter.standard(for: request.situation.destination)
        let pipeline = pipeline ?? Self.pipeline(for: request, under: formatter, steps: steps)
        // Romanised before the passes, so they read and write the Latin letters dictation inserts.
        let draft = pipeline.run(Draft(transcription: request.transcription.romanised))
        return TransformationResult(
            text: draft.text, producedBy: kind,
            cleaning: CleaningRecord(draft: draft, ran: pipeline.ids))
    }

    /// The standard passes for the request's scope: a piece waits for the message to be finished.
    private static func pipeline(
        for request: TransformationRequest, under formatter: DestinationFormatter, steps: CleaningSteps
    ) -> CleaningPipeline {
        switch request.scope {
        case .message: .standard(for: formatter, situation: request.situation, steps: steps)
        case .piece: .piece(numbers: formatter.numbers, digits: formatter.digits, steps: steps)
        }
    }
}
