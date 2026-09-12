public import UttrflowCore

/// Tries engines in preference order, stepping around any that decline; so Hindi skips Apple's model.
public struct TransformerRouter: TranscriptCleaning {
    /// Every transformer this build contains.
    private let engines: [any TextTransformationEngine]
    /// The kinds to try, in order.
    private let preference: [TransformerKind]

    /// Keeps the engines and the kinds to try; the preference should end in one that never declines.
    public init(engines: [any TextTransformationEngine], preference: [TransformerKind]) {
        self.engines = engines
        self.preference = preference
    }

    /// Builds a router from a stored configuration, keeping only kinds this build has.
    public init(engines: [any TextTransformationEngine], configuration: EngineConfiguration) {
        self.init(engines: engines, preference: configuration.resolvedTransformerPreference)
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
        let route = orderedEngines
        let outcome = await FallbackRunner.firstSuccess(among: route) { engine in
            guard await engine.availability(for: request).isAvailable else {
                throw TransformationError.noCapableTransformer
            }
            return try await engine.transform(request)
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

    /// The engines that answered and were refused, which is the half of a fallback nothing else records.
    private static func refusals(
        in errors: [any Error], on route: [TransformerKind]
    ) -> [CleaningRecord.Refusal] {
        errors.enumerated().compactMap { index, error in
            guard case TransformationError.outputRejected(let reason) = error, index < route.count
            else { return nil }
            return CleaningRecord.Refusal(engine: route[index].rawValue, reason: reason)
        }
    }
}
