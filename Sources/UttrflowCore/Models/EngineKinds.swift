/// Which speech-to-text implementation to use.
///
/// Adding an engine means adding a case and registering an implementation; no caller
/// of ``SpeechEngine`` changes.
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
    /// A local open-weight model. Covers languages Foundation Models does not.
    case localModel
    /// Deterministic punctuation, capitalisation and filler removal. Always works.
    case rules
    /// A hosted model. Compiled in only when `UTTRFLOW_CLOUD` is defined.
    case cloud

    /// The kinds a build is allowed to select.
    ///
    /// V1 ships without cloud support, so ``cloud`` is excluded and the app contains
    /// no path that reaches the network.
    /// The kinds a build can actually run.
    ///
    /// This is what makes ``EngineConfiguration/resolvedTransformerPreference`` honest,
    /// and both exclusions are here for the same reason: a preference listing an engine
    /// the binary does not contain is silently dropped at routing time, so the
    /// configuration says one thing and the product does another.
    ///
    /// `.cloud` is compiled in only under `UTTRFLOW_CLOUD`. `.localModel` is compiled in
    /// only under `UTTRFLOW_LOCAL_MODEL`, and the app defines neither: `UttrflowLocalModel`
    /// links MLX, whose Metal shaders need a toolchain the app deliberately does not
    /// require in order to build. It is reachable from the bake-off, which measures it,
    /// and not from the app. Apple's model turned out to handle Hindi — undocumented,
    /// but verified — so the language the local model was brought in for is covered.
    public static var selectable: [TransformerKind] {
        allCases.filter { kind in
            switch kind {
            case .cloud:
                #if UTTRFLOW_CLOUD
                    true
                #else
                    false
                #endif
            case .localModel:
                #if UTTRFLOW_LOCAL_MODEL
                    true
                #else
                    false
                #endif
            case .foundationModels, .rules:
                true
            }
        }
    }
}
