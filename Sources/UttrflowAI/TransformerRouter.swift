public import UttrflowCore

/// Picks the transformer that will actually clean up a given utterance.
///
/// Not a transformer itself: it chooses one. Engines are tried in the order the
/// configuration lists them, and an engine that cannot handle the request — most often
/// because it does not know the spoken language — steps aside rather than producing
/// bad output. That is the whole of how Hindi is routed away from Apple's model, and
/// it is data rather than an `if` statement anywhere.
public struct TransformerRouter: TranscriptCleaning {
    private let engines: [any TextTransformationEngine]
    private let preference: [TransformerKind]

    /// - Parameters:
    ///   - engines: Every transformer this build contains.
    ///   - preference: Kinds to try, in order. Should end in one that can never
    ///     decline, so the router cannot run out of options.
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

    /// Satisfies ``TranscriptCleaning`` so the pipeline can depend on the idea of
    /// cleaning rather than on how an engine gets chosen.
    public func clean(
        _ request: TransformationRequest
    ) async throws(TransformationError) -> TransformationResult {
        try await transform(request)
    }

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
