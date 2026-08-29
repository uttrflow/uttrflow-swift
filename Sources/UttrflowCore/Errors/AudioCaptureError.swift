/// A failure while recording.
public enum AudioCaptureError: UttrflowFailure {
    case noInputDevice
    case alreadyRecording
    case notRecording
    case unsupportedInputFormat
    case engineFailed(description: String)

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

    public var recovery: RecoveryAction? {
        switch self {
        case .noInputDevice, .unsupportedInputFormat: nil
        case .alreadyRecording, .notRecording, .engineFailed: .retry
        }
    }

    public var severity: FailureSeverity {
        switch self {
        // No usable microphone is the end of it: there is nothing to record with, and
        // no route to text that does not start there.
        case .noInputDevice, .unsupportedInputFormat: .blocking
        // The two state assertions and a dropped audio unit are all one-offs that the
        // next press gets past.
        case .alreadyRecording, .notRecording, .engineFailed: .recoverable
        }
    }
}
