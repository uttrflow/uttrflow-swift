public import UttrflowCore

private enum RouterAttemptFailure: Error, Sendable {
    case timedOut(TransformerKind)
    case cancelled
}

/// Tries engines in preference order, stepping around any that decline; so Hindi skips Apple's model.
public struct TransformerRouter: TranscriptCleaning {
    /// Every transformer this build contains.
    private let engines: [any TextTransformationEngine]
    /// The kinds to try, in order.
    private let preference: [TransformerKind]
    /// The user's choices, also used by the pipeline when it joins pieces.
    public let cleaningSteps: CleaningSteps
    /// What each engine's allowance is measured against; injected so a test need not wait out a hang.
    private let clock: any Clock<Duration>
    /// The requests handed straight to the rules when the rules are on the route.
    let rulesAlone: RulesAlone
    /// Where each piece's outcome is counted, so the tally is kept where the record is built.
    private let outcomes: any TidyOutcomeRecording

    /// Keeps the engines and the kinds to try; the preference should end in one that never declines.
    public init(
        engines: [any TextTransformationEngine], preference: [TransformerKind],
        clock: any Clock<Duration> = ContinuousClock(), rulesAlone: RulesAlone = .never,
        cleaningSteps: CleaningSteps = .default,
        outcomes: any TidyOutcomeRecording = NoOpTidyOutcomeRecorder()
    ) {
        self.outcomes = outcomes
        self.engines = engines
        self.preference = preference
        self.cleaningSteps = cleaningSteps
        self.clock = clock
        self.rulesAlone = rulesAlone
    }

    /// Builds a router from a stored configuration, keeping only kinds this build has.
    public init(
        engines: [any TextTransformationEngine], configuration: EngineConfiguration,
        clock: any Clock<Duration> = ContinuousClock(), rulesAlone: RulesAlone = .never,
        cleaningSteps: CleaningSteps = .default,
        outcomes: any TidyOutcomeRecording = NoOpTidyOutcomeRecorder()
    ) {
        self.init(
            engines: engines, preference: configuration.resolvedTransformerPreference, clock: clock,
            rulesAlone: rulesAlone, cleaningSteps: cleaningSteps, outcomes: outcomes)
    }

    /// The engines that will be tried, in order.
    public var route: [TransformerKind] { orderedEngines.map(\.kind) }

    /// The preference list resolved to the engines this build has, in order.
    private var orderedEngines: [any TextTransformationEngine] {
        preference.compactMap { kind in engines.first { $0.kind == kind } }
    }

    /// Satisfies ``TranscriptCleaning``, so the pipeline depends on cleaning rather than on engine choice.
    public func clean(
        _ request: TransformationRequest
    ) async throws(TransformationError) -> TransformationResult {
        try await transform(request)
    }

    /// Runs the message's own passes once over the joined pieces, the way a whole message would have had them.
    public func finishMessage(_ text: String, for request: TransformationRequest) async -> String {
        let formatter = DestinationFormatter.standard(for: request.situation)
        let message = CleaningPipeline.message(
            for: formatter, situation: request.situation, heard: request.transcription.text,
            steps: cleaningSteps, vocabulary: request.vocabulary)
        return message.run(Draft(keepingLineBreaks: text)).text
    }

    /// Warms the route for the last request so its session is ready when the user releases the key.
    public func reserveFinalPiece(_ situation: Situation?) async {
        for engine in orderedEngines { await engine.warm(for: situation) }
    }

    /// Warms every engine on the route for `situation`, since which one will answer is not known yet.
    public func warm(for situation: Situation?) async {
        for engine in preference.compactMap({ kind in engines.first { $0.kind == kind } }) {
            await engine.warm(for: situation)
        }
    }

    /// The result of the first engine on the route that is available and succeeds, or `noCapableTransformer`.
    public func transform(
        _ request: TransformationRequest
    ) async throws(TransformationError) -> TransformationResult {
        let route = candidates(for: request)
        // One deadline for the route, so a second model cannot spend the floor's turn after the first timed out.
        let deadline = Deadline(StageTimeout.route, clock: clock)
        let floorReserve = route.last.map { $0.budget(for: request) } ?? .zero
        let floorKind = route.last?.kind
        var unavailableEngines: [CleaningRecord.UnavailableEngine] = []
        let outcome = await FallbackRunner.firstSuccess(
            among: route,
            stopAfterFailure: { error in
                guard let failure = error as? RouterAttemptFailure else { return false }
                if case .cancelled = failure { return true }
                return false
            }
        ) { [clock] engine in
            guard !Task.isCancelled else { throw RouterAttemptFailure.cancelled }
            let availability = await engine.availability(for: request)
            guard availability.isAvailable else {
                if case .unavailable(let reason) = availability {
                    unavailableEngines.append(
                        .init(engine: engine.kind.rawValue, reason: reason))
                }
                throw TransformationError.noCapableTransformer
            }
            // Its own allowance, cut so the floor's turn always fits inside the route.
            let reserve = engine.kind == floorKind ? .zero : floorReserve
            let allowance = min(engine.budget(for: request), deadline.remaining - reserve)
            guard allowance > .zero else { throw RouterAttemptFailure.timedOut(engine.kind) }
            let answer: TransformationResult?
            do {
                answer = try await withStageTimeout(allowance, clock: clock) {
                    try await engine.transform(request)
                }
            } catch {
                if Task.isCancelled { throw RouterAttemptFailure.cancelled }
                throw error
            }
            guard let answer else {
                if Task.isCancelled { throw RouterAttemptFailure.cancelled }
                throw RouterAttemptFailure.timedOut(engine.kind)
            }
            return answer
        }

        switch outcome {
        case .succeeded(let result, let refused):
            // Carried on the record the Diagnostics page renders, so a plainer dictation has a reason.
            let refusals = Self.refusals(in: refused, on: route.map(\.kind))
            let failures = Self.engineFailures(in: refused)
            guard !refusals.isEmpty || !unavailableEngines.isEmpty || !failures.isEmpty else {
                await outcomes.record(TidyOutcome(finishedBy: result.producedBy, record: nil))
                return result
            }
            var record = result.cleaning ?? CleaningRecord(changes: [])
            if !refusals.isEmpty { record = record.refused(refusals) }
            let routed = CleaningRecord(
                changes: record.changes, switchedOff: record.switchedOff,
                refusals: record.refusals, unavailableEngines: unavailableEngines,
                engineFailures: record.engineFailures + failures, modelAnswers: record.modelAnswers)
            await outcomes.record(TidyOutcome(finishedBy: result.producedBy, record: routed))
            return result.recording(routed)
        case .exhausted(let errors):
            if errors.contains(where: {
                ($0 as? RouterAttemptFailure).map { failure in
                    if case .cancelled = failure { return true }
                    return false
                } ?? false
            }) {
                throw .cancelled
            }
            await outcomes.record(
                TidyOutcome(
                    finishedBy: nil,
                    record: CleaningRecord(
                        changes: [], refusals: Self.refusals(in: errors, on: route.map(\.kind)),
                        unavailableEngines: unavailableEngines,
                        engineFailures: Self.engineFailures(in: errors))))
            throw .noCapableTransformer
        }
    }

    /// The engines to try for `request`: the rules alone for a request they finish, otherwise the whole route.
    private func candidates(for request: TransformationRequest) -> [any TextTransformationEngine] {
        let ordered = orderedEngines
        guard rulesAlone.covers(request), let rules = ordered.first(where: { $0.kind == .rules }) else {
            return ordered
        }
        return [rules]
    }

    /// The engines that answered and were refused, which is the half of a fallback nothing else records.
    private static func refusals(
        in errors: [any Error], on route: [TransformerKind]
    ) -> [CleaningRecord.Refusal] {
        errors.enumerated().compactMap { index, error in
            guard case TransformationError.outputRejected(let reason, let kind) = error, index < route.count
            else { return nil }
            return CleaningRecord.Refusal(engine: route[index].rawValue, reason: reason, kind: kind)
        }
    }

    /// The failures that explain why an earlier engine did not answer, without its error text.
    private static func engineFailures(in errors: [any Error]) -> [CleaningRecord.EngineFailure] {
        errors.compactMap { error in
            let engine: String
            let failureClass: ModelFailureClass
            if let failure = error as? RouterAttemptFailure,
                case .timedOut(let kind) = failure
            {
                engine = kind.rawValue
                failureClass = .timedOut
            } else if let failure = error as? TransformationError,
                case .transformFailed(let kind, let reason) = failure
            {
                engine = kind.rawValue
                failureClass = reason
            } else {
                return nil
            }
            return CleaningRecord.EngineFailure(engine: engine, failureClass: failureClass)
        }
    }
}
