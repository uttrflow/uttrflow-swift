public import Foundation
public import UttrflowCore
public import UttrflowDictionary

/// Builds the transformers a build contains, and the router over them.
///
/// The one place that names concrete engines. Everything above it sees a router.
public enum TextTransformers {
    /// Every transformer compiled into this build; `spellings` is the user's dictionary, read per dictation.
    public static func all(
        cloudEndpoint: URL? = nil, spellings: (@Sendable () async -> PhoneticIndex)? = nil
    ) -> [any TextTransformationEngine] {
        let doubtful = spellings.map { DoubtfulWords.including(dictionary: $0) } ?? .standard
        var engines: [any TextTransformationEngine] = [
            GenerativeTextTransformer(
                kind: .foundationModels, model: AppleFoundationCleanupModel(), doubtful: doubtful),
            RuleBasedTransformer(),
        ]
        #if UTTRFLOW_CLOUD
            if let endpoint = cloudEndpoint {
                engines.append(
                    GenerativeTextTransformer(
                        kind: .cloud, model: HTTPCleanupModel(endpoint: endpoint), doubtful: doubtful)
                )
            }
        #endif
        return engines
    }

    public static func router(
        configuration: EngineConfiguration = .default, cloudEndpoint: URL? = nil,
        spellings: (@Sendable () async -> PhoneticIndex)? = nil
    ) -> TransformerRouter {
        TransformerRouter(
            engines: all(cloudEndpoint: cloudEndpoint, spellings: spellings), configuration: configuration)
    }
}
