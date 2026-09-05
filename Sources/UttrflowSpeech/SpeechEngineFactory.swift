public import Foundation
public import UttrflowCore

/// Builds the speech engine named by the configuration; nothing else mentions a concrete recogniser.
public enum SpeechEngineFactory {
    /// Builds the configured recogniser from an installed `modelFolder`; only WhisperKit takes a vocabulary.
    public static func make(
        kind: SpeechEngineKind,
        model: SpeechModel = .default,
        modelFolder: URL,
        vocabulary: (any VocabularySource)? = nil
    ) -> BackedSpeechEngine {
        switch kind {
        case .whisperKit:
            BackedSpeechEngine(
                kind: .whisperKit,
                backend: WhisperKitBackend(model: model, modelFolder: modelFolder),
                vocabulary: vocabulary
            )
        case .appleSpeech:
            BackedSpeechEngine(kind: .appleSpeech, backend: AppleSpeechBackend())
        }
    }
}
