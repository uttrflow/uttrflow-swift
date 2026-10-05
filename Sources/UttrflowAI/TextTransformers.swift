public import UttrflowCore
public import UttrflowDictionary

/// Builds the transformers a build contains and the router over them; the one place naming concrete engines.
public enum TextTransformers {
    /// Every transformer in this build, running the steps the user left on; `spellings` is their dictionary, `localModel` the loaded open-weight model.
    public static func all(
        steps: CleaningSteps = .default, spellings: (@Sendable () async -> PhoneticIndex)? = nil,
        localModel: (any CleanupModel)? = nil
    ) -> [any TextTransformationEngine] {
        let doubtful = spellings.map { DoubtfulWords.including(dictionary: $0) } ?? .standard
        let open: [any TextTransformationEngine] =
            localModel.map { [local($0, steps: steps, doubtful: doubtful)] } ?? []
        return open + [
            GenerativeTextTransformer(
                kind: .foundationModels, model: AppleFoundationCleanupModel(),
                steps: steps, doubtful: doubtful),
            RuleBasedTransformer(steps: steps),
        ]
    }

    /// The tidier over the open-weight model, the one way the app and the bake-off build it.
    public static func local(
        _ model: any CleanupModel, steps: CleaningSteps = .default, doubtful: DoubtfulWords = .standard
    ) -> GenerativeTextTransformer {
        GenerativeTextTransformer(kind: .localModel, model: model, steps: steps, doubtful: doubtful)
    }

    /// A router over every engine in this build, ordered by the configuration, with short replies left to the rules.
    public static func router(
        configuration: EngineConfiguration = .default, steps: CleaningSteps = .default,
        spellings: (@Sendable () async -> PhoneticIndex)? = nil, localModel: (any CleanupModel)? = nil
    ) -> TransformerRouter {
        TransformerRouter(
            engines: all(steps: steps, spellings: spellings, localModel: localModel),
            configuration: configuration, rulesAlone: .shortReplies, cleaningSteps: steps)
    }
}
