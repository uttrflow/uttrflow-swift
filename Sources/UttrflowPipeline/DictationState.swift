// Where a dictation has got to, how it ended, and what went wrong.
public import UttrflowCore

/// Something that went wrong, carrying the transcript so the user's words stay reachable (§19).
public struct DictationFailure: Sendable, Equatable {
    public let message: String
    public let recovery: RecoveryAction?
    /// How much this cost the user; carried because only the error knows and this is the last place with it.
    public let severity: FailureSeverity
    /// What the user said, when there was anything to salvage.
    public let transcript: String?

    public init(
        message: String, recovery: RecoveryAction?, severity: FailureSeverity,
        transcript: String? = nil
    ) {
        self.message = message
        self.recovery = recovery
        self.severity = severity
        self.transcript = transcript
    }

    /// Builds the notice from any error; the fallback keeps an unforeseen one off the screen as a type name.
    public init(_ error: any Error, transcript: String? = nil) {
        if let failure = error as? any UttrflowFailure {
            self.init(
                message: failure.userMessage, recovery: failure.recovery,
                severity: failure.severity, transcript: transcript)
        } else {
            // Recoverable rather than blocking: an unforeseen error is far more likely a one-off.
            self.init(
                message: "Something went wrong. Please try again.", recovery: .retry,
                severity: .recoverable, transcript: transcript)
        }
    }

    /// The same failure offering a different next step.
    public func offering(_ recovery: RecoveryAction?) -> DictationFailure {
        DictationFailure(message: message, recovery: recovery, severity: severity, transcript: transcript)
    }
}

/// What the product finished doing.
public struct DictationOutcome: Sendable, Equatable {
    public let text: String
    public let method: TextInsertionMethod
    /// Which transformer tidied it. Recorded for evaluation; never shown to users.
    public let cleanedBy: TransformerKind
    /// The application the words went into, read from the tidying context rather than asked again later.
    public let insertedInto: String?
    /// That application's bundle identifier, the identity the interface looks the icon up by.
    public let insertedIntoIdentifier: String?
    /// How long the speaker talked; not a stage measurement, since it is the user's choice, not a cost.
    public let spokenFor: Duration?
    /// Everything Uttrflow changed about what the user said, carried out so nothing is applied silently.
    public let changes: AppliedChanges
    /// Whether this comes from a kept recording rather than the microphone, and is copied, not typed.
    public let isFromRecording: Bool

    public init(
        text: String, method: TextInsertionMethod, cleanedBy: TransformerKind,
        insertedInto: String? = nil, insertedIntoIdentifier: String? = nil,
        spokenFor: Duration? = nil, changes: AppliedChanges = .none, fromRecording: Bool = false
    ) {
        self.text = text
        self.method = method
        self.cleanedBy = cleanedBy
        self.insertedInto = insertedInto
        self.insertedIntoIdentifier = insertedIntoIdentifier
        self.spokenFor = spokenFor
        self.changes = changes
        self.isFromRecording = fromRecording
    }
}

/// Where a dictation has got to (§15); `failed` is a way of leaving that carries what recovery needs.
public enum DictationState: Sendable, Equatable {
    case idle
    case recording
    case transcribing
    case tidying
    case inserted(DictationOutcome)
    case failed(DictationFailure)

    /// Whether a new dictation can begin.
    public var isBusy: Bool {
        switch self {
        case .recording, .transcribing, .tidying: true
        case .idle, .inserted, .failed: false
        }
    }

    /// Whether the microphone is live. Drives the recording indicator.
    public var isListening: Bool { self == .recording }
}
