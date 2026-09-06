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

    /// Warms every engine on the route, since which one will answer is not known yet.
    public func warm() async {
        for engine in preference.compactMap({ kind in engines.first { $0.kind == kind } }) {
            await engine.warm()
        }
    }

    /// The result of the first engine on the route that is available and succeeds, or `noCapableTransformer`.
    public func transform(
        _ request: TransformationRequest
    ) async throws(TransformationError) -> TransformationResult {
        let outcome = await FallbackRunner.firstSuccess(among: orderedEngines) { engine in
            guard await engine.availability(for: request).isAvailable else {
                throw TransformationError.noCapableTransformer
            }
            return try await engine.transform(request)
        }

        switch outcome {
        case .succeeded(let result):
            return result
        case .exhausted:
            throw .noCapableTransformer
        }
    }
}
