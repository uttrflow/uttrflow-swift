public import UttrflowCore

/// Cleans a transcript with any ``CleanupModel`` and refuses a rewrite that changes what the speaker meant.
public struct GenerativeTextTransformer: TextTransformationEngine {
    /// Which engine this stands for.
    public let kind: TransformerKind

    /// The longest allowance this transformer may use; individual requests scale down with their word count.
    public var budget: Duration { .seconds(15) }

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

    /// Reserves the warm slot for the last piece after earlier model requests have consumed theirs.
    public func reserveFinalPiece(_ situation: Situation?) async {
        await warm(for: situation)
    }

    /// Gives short requests a short turn and prevents oversized input from spending the full engine allowance.
    public func budget(for request: TransformationRequest) -> Duration {
        FoundationModelRequestBudget.allowance(
            for: request.transcription.text.split(whereSeparator: \.isWhitespace).count)
    }

    /// Rewrites, unwraps and tidies, then throws `outputRejected` when the meaning guard refuses.
    public func transform(
        _ request: TransformationRequest
    ) async throws(TransformationError) -> TransformationResult {
        let formatter = DestinationFormatter.standard(for: request.situation)
        let pipeline = CleaningPipeline.beforeModel(
            for: formatter, situation: request.situation, steps: steps,
            pauses: request.profile.pauses)
        // The passes go first, so fillers and self-corrections are gone before the model can rewrite them.
        let draft = pipeline.run(Draft(transcription: request.transcription))
        let spoken = draft.text
        // The sources answer in milliseconds and run beside each other, so the readings cost the call nothing.
        let readings = await doubtful.spans(in: draft, for: request.situation)
        // A run the recogniser scored low with a reading offered is the model's to choose, which the rules cannot do.
        if !readings.contains(where: { $0.reason == .lowScore }),
            let floor = try await Self.floorSettles(request, draft: draft, formatter: formatter, steps: steps)
        {
            return floor
        }
        let rewritten = try await model.rewrite(
            prompts.userPrompt(
                for: request, spoken: spoken, doubtful: readings,
                preserving: steps.switchedOff),
            prompt: prompts.conversation(for: request.situation.destination), kind: kind
        )

        // Models echo the shape of the worked examples, so the answer is unwrapped before it is judged.
        let unwrapped = ResponseUnwrapper.unwrap(rewritten, spoken: spoken)
        // An unchanged answer did no work only when the destination still owes the text formatting.
        if Self.isUnchangedAnswer(unwrapped, spoken: spoken, formatter: formatter) {
            throw .outputRejected(
                reason: "the model returned the input unchanged", kind: .unchangedAnswer)
        }
        let finishing =
            request.scope == .piece
            ? CleaningPipeline.afterModelPiece(
                digits: request.situation.digits(for: formatter), situation: request.situation,
                heard: request.transcription.text, spoken: spoken)
            : CleaningPipeline.afterModel(
                for: formatter, situation: request.situation, heard: request.transcription.text,
                spoken: spoken, steps: steps, vocabulary: request.vocabulary)
        let polished = finishing.run(Draft(keepingLineBreaks: TextTidy.collapseSpacing(unwrapped)))
        let finished = polished.text

        // A refusal is not a failure: the router moves on, and the floor beneath it cannot invent anything.
        if case .rejected(let reason, let kind) = meaningGuard.scriptVerdict(
            draft: spoken, rewritten: finished, examples: prompts.allWorkedExamples)
        {
            throw .outputRejected(reason: reason, kind: kind)
        }
        if case .rejected(let reason, let kind) = meaningGuard.verdict(
            draft: draft, rewritten: finished, offering: readings, echoed: Self.echo(in: polished),
            layout: formatter.layout, grammar: formatter.grammar, grants: pipeline.grants)
        {
            throw .outputRejected(reason: reason, kind: kind)
        }

        // Only a taught reading has an entry to count; the screen's and the vocabulary's have none.
        let taken = meaningGuard.readingsTaken(draft: draft, rewritten: finished, offering: readings)
        // The guard judges words, so a mark added where the clause runs on is taken out here, alone.
        let marked = AddedMarkCheck.checked(finished, against: spoken).text
        return TransformationResult(
            text: marked, producedBy: kind,
            cleaning: Self.record(
                before: draft, after: polished, ran: pipeline.ids + finishing.ids, modelAnswer: rewritten),
            entriesTaken: taken.compactMap(\.entryID))
    }

    /// The rules' result when an English draft owes only its capital and stop and the rules settle its ending, so the model has nothing to add.
    private static func floorSettles(
        _ request: TransformationRequest, draft: Draft, formatter: DestinationFormatter, steps: CleaningSteps
    ) async throws(TransformationError) -> TransformationResult? {
        guard request.effectiveLanguage == .english,
            formatter.owesFormatting(TextTidy.collapseSpacing(draft.text))
        else { return nil }
        let tokens = MeaningPreservationGuard.grammarTokens(draft.text)
        // Romanised Hindi reads as English to the recogniser, so the words are checked as well as the tag.
        guard !MeaningPreservationGuard.hasRomanisedHindiContext(tokens),
            // A mark's name the rules kept as a word is one they could not settle: "note colon kal".
            !tokens.contains(where: { SpokenPunctuationPass.ordinaryNames.contains([$0.matching]) }),
            !QuestionShape.opensQuestionLater(draft.presentIndices.map(draft.shape(at:)))
        else { return nil }
        let floor = try await RuleBasedTransformer(steps: steps).transform(request)
        let unchanged =
            MeaningPreservationGuard.grammarTokens(floor.text).map(\.matching) == tokens.map(\.matching)
        return unchanged ? floor : nil
    }

    /// One account of the passes on both sides of the model, a step that ran on both sides counted once.
    private static func record(
        before: Draft, after: Draft, ran: [PassID], modelAnswer: String
    ) -> CleaningRecord {
        CleaningRecord.merging([
            CleaningRecord(draft: before, ran: ran),
            CleaningRecord(draft: after, ran: ran, modelAnswers: [modelAnswer]),
        ])
    }

    /// The caret's echo the finishing pipeline took back, which the model did answer with and the guard must see.
    private static func echo(in draft: Draft) -> String {
        draft.words.filter { $0.state == .removed(by: CaretEchoPass.id) }.map(\.text)
            .joined(separator: " ")
    }

    /// Whether the model's answer is what the speaker said while the destination still owes it formatting.
    private static func isUnchangedAnswer(
        _ rewritten: String, spoken: String, formatter: DestinationFormatter
    ) -> Bool {
        let spokenCollapsed = TextTidy.collapseSpacing(spoken)
        guard TextTidy.collapseSpacing(rewritten) == spokenCollapsed else { return false }
        // A short reply is accepted as it stands; a fragment is too little to judge.
        guard spokenCollapsed.split(whereSeparator: \.isWhitespace).count > 3 else { return false }
        return formatter.owesFormatting(spokenCollapsed)
    }
}
