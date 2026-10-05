// The words every recovery button uses.
public import UttrflowCore

/// The one title assigned to each recovery action.
public enum RecoveryActionTitle {
    /// Names the action the button performs.
    public static func title(for recovery: RecoveryAction) -> String {
        switch recovery {
        case .openSystemSettings: "Open System Settings"
        case .retry: "Try Again"
        case .downloadSpeechModel: "Finish Setup"
        case .pasteManually: "Dismiss"
        case .showHistory: "Show History"
        case .copyTranscript: "Copy"
        case .retryFromRecording: "Retry"
        }
    }
}
