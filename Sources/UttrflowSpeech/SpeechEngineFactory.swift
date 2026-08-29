public import Foundation
public import UttrflowCore

/// Builds the speech engine named by the configuration.
///
/// The whole of "switching recogniser is a flag" lives in this one switch. Nothing
/// else in the product mentions a concrete recogniser.
public enum SpeechEngineFactory {
    /// Builds the recogniser a build is configured to use.
    ///
    /// - Parameters:
    ///   - kind: Which recogniser to build.
    ///   - model: The speech model, for the recognisers that need one.
    ///   - modelFolder: Where that model already is. Nothing here downloads.
    ///   - vocabulary: Words to bias the recogniser towards, asked for once per
    ///     dictation. Only WhisperKit can use it — Apple's recogniser has no equivalent,
    ///     so it is not offered one rather than handed something it would ignore.
    /// - Returns: An engine that hides which recogniser is behind it.
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
