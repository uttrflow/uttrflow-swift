// The catalogue of engine kinds a configuration can name.

/// Which speech-to-text implementation to use; a new engine is a case here and an implementation, no more.
public enum SpeechEngineKind: String, Sendable, Equatable, CaseIterable, Codable {
    /// WhisperKit running a local Whisper model. Multilingual, highest accuracy.
    case whisperKit
    /// The system `SpeechTranscriber`. No download, lowest latency.
    case appleSpeech
}

/// Which text-clean-up implementation to use.
public enum TransformerKind: String, Sendable, Equatable, CaseIterable, Codable {
    /// Apple's on-device Foundation Models. Free and fast, but only some languages.
    case foundationModels
    /// A local open-weight model. Measured in the bake-off only; no build assembles it. See `Docs/core-engine-kinds.md`.
    case localModel
    /// Deterministic punctuation, capitalisation and filler removal. Always works.
    case rules
    /// A hosted model. Compiled in only when `UTTRFLOW_CLOUD` is defined.
    case cloud
    /// Nothing tidied the words: every engine was starved or refused, so the transcript went in as heard.
    case untidied

    /// The kinds this binary contains; the app defines no build flag here. See `Docs/core-engine-kinds.md`.
    public static var selectable: [TransformerKind] {
        allCases.filter { kind in
            switch kind {
            case .cloud:
                #if UTTRFLOW_CLOUD
                    true
                #else
                    false
                #endif
            case .foundationModels, .rules:
                true
            // MLX is quarantined behind UttrflowLocalModel; no transformer assembly may link it, so this is never selectable.
            case .localModel:
                false
            // Not an engine anybody can choose: it is what the record says when none of them ran.
            case .untidied:
                false
            }
        }
    }
}
