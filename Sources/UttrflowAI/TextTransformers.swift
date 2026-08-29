public import Foundation
public import UttrflowCore

/// Builds the transformers a build contains, and the router over them.
///
/// The one place that names concrete engines. Everything above it sees a router.
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

    public static func router(
        configuration: EngineConfiguration = .default, cloudEndpoint: URL? = nil
    ) -> TransformerRouter {
        TransformerRouter(engines: all(cloudEndpoint: cloudEndpoint), configuration: configuration)
    }
}
