/// A failure while recording.
public enum AudioCaptureError: UttrflowFailure {
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
        case .noInputDevice:
            "No microphone was found. Connect one and try again."
        case .alreadyRecording:
            "Recording is already in progress."
        case .notRecording:
            "There is no recording to stop."
        case .unsupportedInputFormat:
            "This microphone's audio format isn't supported."
        case .engineFailed:
            "Recording stopped unexpectedly. Try again."
        }
    }

    /// A retry for a one-off; nothing for a missing or unusable microphone.
    public var recovery: RecoveryAction? {
        switch self {
        case .noInputDevice, .unsupportedInputFormat: nil
        case .alreadyRecording, .notRecording, .engineFailed: .retry
        }
    }

    /// Blocking without a usable microphone, since every route to text starts there; recoverable otherwise.
    public var severity: FailureSeverity {
        switch self {
        // No usable microphone is the end of it: nothing to record with.
        case .noInputDevice, .unsupportedInputFormat: .blocking
        // The two state assertions and a dropped audio unit are one-offs the next press gets past.
        case .alreadyRecording, .notRecording, .engineFailed: .recoverable
        }
    }
}
