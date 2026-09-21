public import UttrflowCore

/// Tries engines in preference order, stepping around any that decline; so Hindi skips Apple's model.
public struct TransformerRouter: TranscriptCleaning {
    /// Every transformer this build contains.
    private let engines: [any TextTransformationEngine]
    /// The kinds to try, in order.
    private let preference: [TransformerKind]
    /// What each engine's allowance is measured against; injected so a test need not wait out a hang.
    private let clock: any Clock<Duration>
    /// The requests handed straight to the rules when the rules are on the route.
    let rulesAlone: RulesAlone

    /// Keeps the engines and the kinds to try; the preference should end in one that never declines.
    public init(
        engines: [any TextTransformationEngine], preference: [TransformerKind],
        clock: any Clock<Duration> = ContinuousClock(), rulesAlone: RulesAlone = .never
    ) {
        self.engines = engines
        self.preference = preference
        self.clock = clock
        self.rulesAlone = rulesAlone
    }

    /// Builds a router from a stored configuration, keeping only kinds this build has.
    public init(
        engines: [any TextTransformationEngine], configuration: EngineConfiguration,
        clock: any Clock<Duration> = ContinuousClock(), rulesAlone: RulesAlone = .never
    ) {
        self.init(
            engines: engines, preference: configuration.resolvedTransformerPreference, clock: clock,
            rulesAlone: rulesAlone)
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
        let formatter = DestinationFormatter.standard(for: request.situation.destination)
        let message = CleaningPipeline.message(
            for: formatter, situation: request.situation, heard: request.transcription.text)
        return message.run(Draft(keepingLineBreaks: text)).text
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
        let outcome = await FallbackRunner.firstSuccess(among: route) { [clock] engine in
            guard await engine.availability(for: request).isAvailable else {
                throw TransformationError.noCapableTransformer
            }
            // Its own allowance, so an engine that hangs spends nothing but its own turn.
            let answer = try await withStageTimeout(engine.budget, clock: clock) {
                try await engine.transform(request)
            }
            guard let answer else {
                throw TransformationError.transformFailed(
                    kind: engine.kind, description: "took longer than its \(engine.budget)")
            }
            return answer
        }

        switch outcome {
        case .succeeded(let result, let refused):
            // Carried on the record the Diagnostics page renders, so a plainer dictation has a reason.
            let refusals = Self.refusals(in: refused, on: route.map(\.kind))
            guard !refusals.isEmpty else { return result }
            return result.recording((result.cleaning ?? CleaningRecord(changes: [])).refused(refusals))
        case .exhausted:
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
}
