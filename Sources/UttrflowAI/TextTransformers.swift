public import Foundation
public import UttrflowCore
public import UttrflowDictionary

/// Builds the transformers a build contains and the router over them; the one place naming concrete engines.
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

    /// A router over every engine in this build, ordered by the configuration.
    public static func router(
        configuration: EngineConfiguration = .default, cloudEndpoint: URL? = nil,
        steps: CleaningSteps = .default, spellings: (@Sendable () async -> PhoneticIndex)? = nil
    ) -> TransformerRouter {
        TransformerRouter(
            engines: all(cloudEndpoint: cloudEndpoint, steps: steps, spellings: spellings),
            configuration: configuration)
    }
}
