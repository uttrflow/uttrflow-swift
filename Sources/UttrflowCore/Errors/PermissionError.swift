/// Something the user must grant before the pipeline can run.
public enum PermissionError: UttrflowFailure {
    case microphoneDenied
    case microphoneRestricted
    case accessibilityNotTrusted

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

    public var recovery: RecoveryAction? {
        switch self {
        case .microphoneDenied: .openSystemSettings(.microphone)
        case .microphoneRestricted: nil
        case .accessibilityNotTrusted: .openSystemSettings(.accessibility)
        }
    }

    public var severity: FailureSeverity {
        switch self {
        // Both microphone refusals stop dictation dead, whether or not the user is the
        // one who can lift them.
        case .microphoneDenied, .microphoneRestricted: .blocking
        // Without Accessibility the words are still captured and still tidied; they
        // arrive on the clipboard rather than in the app the user was typing into.
        case .accessibilityNotTrusted: .degraded
        }
    }
}
