/// A failure while recording.
public enum AudioCaptureError: UttrflowFailure {
    /// macOS has not granted this process microphone access.
    case microphoneDenied
    /// No microphone is connected.
    case noInputDevice
    /// `start` while already recording.
    case alreadyRecording
    /// `stop` while idle.
    case notRecording
    /// The microphone's format cannot be converted.
    case unsupportedInputFormat
    /// The audio unit stopped on its own.
    case engineFailed(description: String)

    /// A plain sentence per case.
    public var userMessage: String {
        switch self {
        case .microphoneDenied:
            "Microphone access is required. Turn it on in System Settings to start dictating."
        case .noInputDevice:
            "No microphone was found. Connect one and try again."
        case .alreadyRecording:
            "The microphone was still busy, so this dictation didn't start. Try again."
        case .notRecording:
            "Recording had already ended, so nothing was captured. Try again."
        case .unsupportedInputFormat:
            "This microphone's audio format isn't supported."
        case .engineFailed:
            "Recording stopped unexpectedly. Try again."
        }
    }

    /// The failure without its remedy, so a kept recording can replace the advice to try again.
    public var cause: String {
        switch self {
        case .noInputDevice: "No microphone was found."
        case .alreadyRecording: "The microphone was still busy, so this dictation didn't start."
        case .notRecording: "Recording had already ended."
        case .engineFailed: "Recording stopped unexpectedly."
        case .microphoneDenied, .unsupportedInputFormat: userMessage
        }
    }

    /// The Microphone pane where access is refused, a retry for a one-off, nothing for unusable hardware.
    public var recovery: RecoveryAction? {
        switch self {
        case .microphoneDenied: .openSystemSettings(.microphone)
        case .noInputDevice, .unsupportedInputFormat: nil
        case .alreadyRecording, .notRecording, .engineFailed: .retry
        }
    }

    /// Blocking without a usable microphone, since every route to text starts there; recoverable otherwise.
    public var severity: FailureSeverity {
        switch self {
        // No usable microphone is the end of it: nothing to record with.
        case .microphoneDenied, .noInputDevice, .unsupportedInputFormat: .blocking
        // The two state assertions and a dropped audio unit are one-offs the next press gets past.
        case .alreadyRecording, .notRecording, .engineFailed: .recoverable
        }
    }
}
