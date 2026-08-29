/// The single place that decides which implementations the pipeline runs.
///
/// Changing engine — to the system transcriber, to a local model, to a hosted model
/// once one exists — is a change to this value and nothing else. No call site, view
/// or view model refers to a concrete engine type.
public struct EngineConfiguration: Sendable, Equatable, Codable {
    /// The speech-to-text implementation.
    public var speech: SpeechEngineKind

    /// Clean-up implementations in preference order.
    ///
    /// The first entry that reports itself able to handle a given request wins, so a
    /// transformer that cannot cope with the detected language steps aside instead of
    /// producing bad output. The list should always end in a kind that can handle
    /// anything — ``TransformerKind/rules`` — so the pipeline cannot dead-end.
    public var transformerPreference: [TransformerKind]

    public init(speech: SpeechEngineKind, transformerPreference: [TransformerKind]) {
        self.speech = speech
        self.transformerPreference = transformerPreference
    }

    /// What V1 ships with: Whisper for speech, Apple's model where it is capable, a
    /// local model for the languages it is not, and rules as the guaranteed floor.
    public static let `default` = EngineConfiguration(
        speech: .whisperKit,
        transformerPreference: [.foundationModels, .localModel, .rules]
    )

    /// Preferences that a build is permitted to run, in order.
    ///
    /// Filters out kinds excluded at compile time so a configuration decoded from an
    /// older or newer build cannot select an engine this binary does not contain.
    public var resolvedTransformerPreference: [TransformerKind] {
        let selectable = Set(TransformerKind.selectable)
        return transformerPreference.filter(selectable.contains)
    }
}
