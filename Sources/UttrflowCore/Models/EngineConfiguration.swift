/// The one place that decides which implementations the pipeline runs; no call site names a concrete engine.
public struct EngineConfiguration: Sendable, Equatable, Codable {
    /// The speech-to-text implementation.
    public var speech: SpeechEngineKind

    /// Clean-up kinds in preference order; the first able to take a request wins, so the list ends in `rules`.
    public var transformerPreference: [TransformerKind]

    /// A configuration naming every engine explicitly.
    public init(speech: SpeechEngineKind, transformerPreference: [TransformerKind]) {
        self.speech = speech
        self.transformerPreference = transformerPreference
    }

    /// What ships: Whisper for speech, Apple's model where capable, a local model otherwise, rules as floor.
    public static let `default` = EngineConfiguration(
        speech: .whisperKit,
        transformerPreference: [.foundationModels, .localModel, .rules]
    )

    /// The preference without the kinds this binary lacks, whatever build wrote the configuration.
    public var resolvedTransformerPreference: [TransformerKind] {
        let selectable = Set(TransformerKind.selectable)
        return transformerPreference.filter(selectable.contains)
    }
}
