/// A failure while turning audio into text.
public enum SpeechEngineError: UttrflowFailure {
    /// The speech model has not been downloaded yet.
    case modelNotInstalled
    /// The download did not complete.
    case modelDownloadFailed(description: String)
    /// The model is on disk but would not load.
    case modelLoadFailed(description: String)
    /// The recording is shorter than anything the recogniser can use.
    case audioTooShort
    /// Held the shortcut and said nothing the recogniser could use.
    case nothingHeard
    /// The recogniser ran and failed.
    case transcriptionFailed(description: String)

    /// A plain sentence per case, never naming the engine.
    public var userMessage: String {
        switch self {
        case .modelNotInstalled:
            "Speech recognition needs to finish setting up before you can dictate."
        case .modelDownloadFailed:
            "Setup couldn't be completed. Check your connection and try again."
        case .modelLoadFailed:
            "Speech recognition couldn't start. Try again, or reinstall it from Settings."
        case .audioTooShort:
            "That was too short to transcribe. Hold the shortcut a moment longer."
        case .nothingHeard:
            "Didn't catch that."
        case .transcriptionFailed:
            "Your speech couldn't be transcribed. Try again."
        }
    }

    /// The model download where the model is missing, a retry where it is not, and nothing for silence.
    public var recovery: RecoveryAction? {
        switch self {
        case .modelNotInstalled, .modelDownloadFailed: .downloadSpeechModel
        case .modelLoadFailed, .audioTooShort, .transcriptionFailed: .retry
        // Nothing to press: the remedy is to speak again, which the shortcut already is.
        case .nothingHeard: nil
        }
    }

    /// Informational for silence, which is not a fault; recoverable for the rest, which a retry gets past.
    public var severity: FailureSeverity {
        switch self {
        // Silence is drawn grey with a single "Got it", so it cannot be mistaken for a broken transcription.
        case .audioTooShort, .nothingHeard: .informational
        // Setup keeps its progress, so asking again resumes rather than restarting the download.
        case .modelNotInstalled, .modelDownloadFailed, .modelLoadFailed, .transcriptionFailed:
            .recoverable
        }
    }
}
