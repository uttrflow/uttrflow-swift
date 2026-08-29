/// A failure while turning audio into text.
public enum SpeechEngineError: UttrflowFailure {
    case modelNotInstalled
    case modelDownloadFailed(description: String)
    case modelLoadFailed(description: String)
    case audioTooShort
    /// Held the shortcut and said nothing the recogniser could use.
    case nothingHeard
    case transcriptionFailed(description: String)

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

    public var recovery: RecoveryAction? {
        switch self {
        case .modelNotInstalled, .modelDownloadFailed: .downloadSpeechModel
        case .modelLoadFailed, .audioTooShort, .transcriptionFailed: .retry
        // Nothing to press. The remedy is to speak again, which the shortcut already
        // is, and a button that only repeats what the user was about to do anyway is
        // one more thing between them and saying it.
        case .nothingHeard: nil
        }
    }

    public var severity: FailureSeverity {
        switch self {
        // Half a second of silence is not a fault, and the design draws it grey with a
        // single "Got it" for that reason. Without this it would be indistinguishable
        // from a transcription that genuinely broke.
        // Neither of these is a fault. Silence used to be handled by returning quietly
        // to idle, which is indistinguishable from the app being broken: the user holds
        // the key, speaks, lets go, and nothing whatever happens.
        case .audioTooShort, .nothingHeard: .informational
        // The rest are one-offs. Setup in particular keeps its progress, so asking
        // again resumes rather than starting the download over.
        case .modelNotInstalled, .modelDownloadFailed, .modelLoadFailed, .transcriptionFailed:
            .recoverable
        }
    }
}
