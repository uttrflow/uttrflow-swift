public import UttrflowCore

/// Cleans a transcript with any ``CleanupModel`` and refuses a rewrite that changes what the speaker meant.
public struct GenerativeTextTransformer: TextTransformationEngine {
    /// Which engine this stands for.
    public let kind: TransformerKind

    /// The model that rewrites.
    private let model: any CleanupModel
    private let prompts: PromptBuilder
    private let meaningGuard: MeaningPreservationGuard
    /// Which passes the user has left on; where they run is the request's to say, not this value's.
    private let steps: CleaningSteps
    private let doubtful: DoubtfulWords

    /// The passes run before the model are built per request, so the destination's own policies reach them.
    public init(
        kind: TransformerKind,
        model: any CleanupModel,
        prompts: PromptBuilder = .standard,
        meaningGuard: MeaningPreservationGuard = MeaningPreservationGuard(),
        steps: CleaningSteps = .default,
        doubtful: DoubtfulWords = .standard
    ) {
        self.kind = kind
        self.model = model
        self.prompts = prompts
        self.meaningGuard = meaningGuard
        self.steps = steps
        self.doubtful = doubtful
    }

    /// Passes the model's own verdict on the spoken language straight through.
    public func availability(for request: TransformationRequest) async -> TransformerAvailability {
        await model.availability(for: request.effectiveLanguage)
    }

    /// Hands the model the instructions for where the words are going, plain text's when that is not known.
    public func warm(for situation: Situation?) async {
        await model.warm(instructions: prompts.instructions(for: situation?.destination ?? .plain))
    }

    /// Rewrites, unwraps and tidies, then throws `outputRejected` when the meaning guard refuses.
    public func transform(
        _ request: TransformationRequest
    ) async throws(TransformationError) -> TransformationResult {
        let formatter = DestinationFormatter.standard(for: request.situation.destination)
        let pipeline = CleaningPipeline.beforeModel(
            for: formatter, situation: request.situation, steps: steps)
        // The passes go first, so fillers and self-corrections are gone before the model can rewrite them.
        let draft = pipeline.run(Draft(transcription: request.transcription))
        let spoken = draft.text
        // The sources answer in milliseconds and run beside each other, so the readings cost the call nothing.
        let readings = await doubtful.spans(in: draft, for: request.situation)
        let rewritten = try await model.rewrite(
            prompts.userPrompt(for: request, spoken: spoken, doubtful: readings),
            instructions: prompts.instructions(for: request.situation.destination), kind: kind
        )

        // Models echo the shape of the worked examples, so the answer is unwrapped before it is judged.
        let unwrapped = ResponseUnwrapper.unwrap(rewritten, spoken: spoken)
        let finishing =
            request.scope == .piece
            ? CleaningPipeline.afterModelPiece(situation: request.situation)
            : CleaningPipeline.afterModel(
                for: formatter, situation: request.situation, heard: request.transcription.text)
        let polished = finishing.run(Draft(keepingLineBreaks: TextTidy.collapseSpacing(unwrapped)))
        let finished = polished.text

        // A refusal is not a failure: the router moves on, and the floor beneath it cannot invent anything.
        if case .rejected(let reason) = meaningGuard.scriptVerdict(
            draft: spoken, rewritten: finished, examples: prompts.allWorkedExamples)
        {
            throw .outputRejected(reason: reason)
        }
        if case .rejected(let reason) = meaningGuard.verdict(
            draft: draft, rewritten: finished, offering: readings, echoed: Self.echo(in: polished),
            layout: formatter.layout, grants: pipeline.grants)
        {
            throw .outputRejected(reason: reason)
        }

        // Only a taught reading has an entry to count; the screen's and the vocabulary's have none.
        let taken = meaningGuard.readingsTaken(draft: draft, rewritten: finished, offering: readings)
        return TransformationResult(
            text: finished, producedBy: kind,
            cleaning: CleaningRecord(draft: draft, ran: pipeline.ids),
            entriesTaken: taken.compactMap(\.entryID))
    }

    /// The caret's echo the finishing pipeline took back, which the model did answer with and the guard must see.
    private static func echo(in draft: Draft) -> String {
        draft.words.filter { $0.state == .removed(by: CaretEchoPass.id) }.map(\.text)
            .joined(separator: " ")
    }
}
