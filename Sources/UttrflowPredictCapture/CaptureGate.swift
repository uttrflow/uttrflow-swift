// Every reason a finished value may not be learned, and the answer the capture path asks for.
private import UttrflowClipboard
private import UttrflowPredict

/// Why a value the user finished entering was not remembered.
public enum CaptureRefusal: String, Sendable, Equatable, CaseIterable {
    /// The field hides what is typed into it, so what it holds is never read.
    case secureField
    /// The user has not been asked about this application yet.
    case consentNotGiven
    /// The user said no to this application.
    case consentDeclined
    /// The value has the shape of a credential.
    case looksLikeSecret
    /// The value would destroy data if it were ever completed and run.
    case destructive
    /// The value is too short to ever be worth completing.
    case tooShort

    /// Whether this refusal is the one the user should be asked about, rather than a silent no.
    public var asksTheUser: Bool { self == .consentNotGiven }
}

/// Every reason not to write, consulted before a value can reach the corpus.
public enum CaptureGate {
    /// The shortest value worth remembering, below which a completion could never save a keystroke.
    public static let minimumLength = 2

    /// Why this value may not be recorded, or nothing when it may.
    public static func refusal(
        toRecord text: String, from reading: FieldReading, given preferences: CapturePreferences
    ) -> CaptureRefusal? {
        guard !reading.isSecure else { return .secureField }
        switch preferences.decision(for: reading.bundleIdentifier) {
        case .refuseAndAsk: return .consentNotGiven
        case .refuseQuietly: return .consentDeclined
        case .proceed: break
        }
        guard text.count >= minimumLength else { return .tooShort }
        if looksLikeSecret(text) { return .looksLikeSecret }
        // A destructive command is never stored, so it can never be one keystroke from running.
        return DestructiveCommand.matches(text) ? .destructive : nil
    }

    /// Whether a value has the shape of a credential, asked of the rules the clipboard already uses.
    public static func looksLikeSecret(_ text: String) -> Bool { SecretShapes.matches(text) }
}
