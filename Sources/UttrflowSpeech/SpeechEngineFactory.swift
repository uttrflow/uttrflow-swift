// The one switch that names a concrete recogniser.
public import Foundation
public import UttrflowCore

/// Builds the speech engine named by the configuration; nothing else mentions a concrete recogniser.
public enum SpeechEngineFactory {
    /// Builds the configured recogniser from an installed `modelFolder`.
    public static func make(
        kind: SpeechEngineKind,
        model: SpeechModel = .default,
        modelFolder: URL,
        prewarm: Bool = true,  // Only a measurement harness passes false; see Docs/performance-dictation.md.
        compute: SpeechComputePlan = .shipping,  // Only a measurement harness passes another plan.
        fallback: SpeechFallbackPlan = .shipping,  // Only a measurement harness passes another plan.
        loadLog: SpeechModelLoadLog? = nil,
        phraseBias: Float = 0,  // Off until a measurement shows a gain; see Docs/speech-phrase-bias.md.
        promptWords: Bool = true,  // Only a measurement harness passes false.
        idleAfter: Duration? = nil,
        didRelease: (@Sendable () -> Void)? = nil,
        didLoad: (@Sendable () -> Void)? = nil,
        willLoad: (@Sendable () -> Void)? = nil
    ) -> BackedSpeechEngine {
        switch kind {
        case .whisperKit:
            BackedSpeechEngine(
                kind: .whisperKit,
                backend: WhisperKitBackend(
                    model: model, modelFolder: modelFolder, prewarm: prewarm, compute: compute,
                    fallback: fallback, loadLog: loadLog, phraseBias: phraseBias,
                    promptWords: promptWords),
                idleAfter: idleAfter,
                didRelease: didRelease,
                didLoad: didLoad,
                willLoad: willLoad
            )
        }
    }
}
