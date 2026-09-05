/// Something the user must grant before the pipeline can run.
public enum PermissionError: UttrflowFailure {
    /// The user refused microphone access.
    case microphoneDenied
    /// A device policy blocks microphone access.
    case microphoneRestricted
    /// This process is not trusted for Accessibility.
    case accessibilityNotTrusted

    /// A plain sentence per case.
    public var userMessage: String {
        switch self {
        case .microphoneDenied:
            "Microphone access is required. Turn it on in System Settings to start dictating."
        case .microphoneRestricted:
            "Microphone access is blocked by a device policy, so dictation cannot start."
        case .accessibilityNotTrusted:
            "Accessibility access is required to insert text into other applications."
        }
    }

    /// The System Settings pane that grants it, or nothing when a policy holds it.
    public var recovery: RecoveryAction? {
        switch self {
        case .microphoneDenied: .openSystemSettings(.microphone)
        case .microphoneRestricted: nil
        case .accessibilityNotTrusted: .openSystemSettings(.accessibility)
        }
    }

    /// Blocking without a microphone; degraded without Accessibility, as the words still reach the clipboard.
    public var severity: FailureSeverity {
        switch self {
        // Both microphone refusals stop dictation dead, whoever can lift them.
        case .microphoneDenied, .microphoneRestricted: .blocking
        // The words are still captured and tidied; they arrive on the clipboard instead of in the app.
        case .accessibilityNotTrusted: .degraded
        }
    }
}
