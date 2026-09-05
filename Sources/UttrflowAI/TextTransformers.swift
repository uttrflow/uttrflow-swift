public import Foundation
public import UttrflowCore

/// Builds the transformers a build contains, and the router over them.
///
/// The one place that names concrete engines. Everything above it sees a router.
public enum TextTransformers {
    /// Every transformer compiled into this build, running the clean-up steps the user has left on.
    public static func all(
        cloudEndpoint: URL? = nil, steps: CleaningSteps = .default
    ) -> [any TextTransformationEngine] {
        var engines: [any TextTransformationEngine] = [
            GenerativeTextTransformer(
                kind: .foundationModels, model: AppleFoundationCleanupModel(),
                pipeline: .beforeModel(steps: steps)),
            RuleBasedTransformer(steps: steps),
        ]
        #if UTTRFLOW_CLOUD
            if let endpoint = cloudEndpoint {
                engines.append(
                    GenerativeTextTransformer(
                        kind: .cloud, model: HTTPCleanupModel(endpoint: endpoint),
                        pipeline: .beforeModel(steps: steps))
                )
            }
        #endif
        return engines
    }

    public static func router(
        configuration: EngineConfiguration = .default, cloudEndpoint: URL? = nil,
        steps: CleaningSteps = .default
    ) -> TransformerRouter {
        TransformerRouter(
            engines: all(cloudEndpoint: cloudEndpoint, steps: steps), configuration: configuration)
    }
}
