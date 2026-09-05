public import Foundation
public import UttrflowCore
public import UttrflowDictionary

/// Builds the transformers a build contains, and the router over them.
///
/// The one place that names concrete engines. Everything above it sees a router.
public enum TextTransformers {
    /// Every transformer in this build, running the steps the user left on; `spellings` is their dictionary.
    public static func all(
        cloudEndpoint: URL? = nil, steps: CleaningSteps = .default,
        spellings: (@Sendable () async -> PhoneticIndex)? = nil
    ) -> [any TextTransformationEngine] {
        let doubtful = spellings.map { DoubtfulWords.including(dictionary: $0) } ?? .standard
        var engines: [any TextTransformationEngine] = [
            GenerativeTextTransformer(
                kind: .foundationModels, model: AppleFoundationCleanupModel(),
                pipeline: .beforeModel(steps: steps), doubtful: doubtful),
            RuleBasedTransformer(steps: steps),
        ]
        #if UTTRFLOW_CLOUD
            if let endpoint = cloudEndpoint {
                engines.append(
                    GenerativeTextTransformer(
                        kind: .cloud, model: HTTPCleanupModel(endpoint: endpoint),
                        pipeline: .beforeModel(steps: steps), doubtful: doubtful)
                )
            }
        #endif
        return engines
    }

    public static func router(
        configuration: EngineConfiguration = .default, cloudEndpoint: URL? = nil,
        steps: CleaningSteps = .default, spellings: (@Sendable () async -> PhoneticIndex)? = nil
    ) -> TransformerRouter {
        TransformerRouter(
            engines: all(cloudEndpoint: cloudEndpoint, steps: steps, spellings: spellings),
            configuration: configuration)
    }
}
