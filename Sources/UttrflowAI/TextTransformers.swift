public import Foundation
public import UttrflowCore

/// Builds the transformers a build contains and the router over them; the one place naming concrete engines.
public enum TextTransformers {
    /// Every transformer compiled into this build.
    public static func all(cloudEndpoint: URL? = nil) -> [any TextTransformationEngine] {
        var engines: [any TextTransformationEngine] = [
            GenerativeTextTransformer(kind: .foundationModels, model: AppleFoundationCleanupModel()),
            RuleBasedTransformer(),
        ]
        #if UTTRFLOW_CLOUD
            if let endpoint = cloudEndpoint {
                engines.append(
                    GenerativeTextTransformer(kind: .cloud, model: HTTPCleanupModel(endpoint: endpoint))
                )
            }
        #endif
        return engines
    }

    /// A router over every engine in this build, ordered by the configuration.
    public static func router(
        configuration: EngineConfiguration = .default, cloudEndpoint: URL? = nil
    ) -> TransformerRouter {
        TransformerRouter(engines: all(cloudEndpoint: cloudEndpoint), configuration: configuration)
    }
}
