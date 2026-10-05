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

    /// What ships: Whisper for speech, Apple's model where capable, rules as the floor.
    /// `localModel` stays in the stored preference so configurations can name every engine;
    /// `resolvedTransformerPreference` removes engines this binary does not assemble.
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
