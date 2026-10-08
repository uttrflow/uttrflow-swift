/// The one place that decides which implementations the pipeline runs; no call site names a concrete engine.
public struct EngineConfiguration: Sendable, Equatable, Codable {
    /// The speech-to-text implementation.
    public var speech: SpeechEngineKind

    /// Clean-up kinds in preference order; the first able to take a request wins, so the list ends in rules.
    public var transformerPreference: [TransformerKind]

    /// A configuration naming every engine explicitly.
    public init(speech: SpeechEngineKind, transformerPreference: [TransformerKind]) {
        self.speech = speech
        self.transformerPreference = transformerPreference
    }

    /// What ships: Whisper for speech, the local model while loaded, Apple's model otherwise, rules as floor.
    public static let `default` = EngineConfiguration(
        speech: .whisperKit,
        transformerPreference: [.localModel, .foundationModels, .rules]
    )

    /// The preference without the kinds this binary lacks, whatever build wrote the configuration.
    public var resolvedTransformerPreference: [TransformerKind] {
        let selectable = Set(TransformerKind.selectable)
        return transformerPreference.filter(selectable.contains)
    }
}

extension EngineConfiguration {
    /// Keeps readable fields and transformer entries when a saved configuration contains unknown values.
    public init(from decoder: any Decoder) throws {
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
            self = .default
            return
        }
        self.init(
            speech: (try? container.decode(SpeechEngineKind.self, forKey: .speech)) ?? Self.default.speech,
            transformerPreference: container.readableElements(
                of: TransformerKind.self, forKey: .transformerPreference,
                fallback: Self.default.transformerPreference))
    }
}
