public import UttrflowCore

/// Something that went wrong, in the form the interface needs it.
///
/// Carries the transcript alongside the message because §19 is explicit: whatever
/// fails, the user's words must stay reachable. A failure that has words to offer is a
/// different thing to show than one that does not.
public struct DictationFailure: Sendable, Equatable {
    public let message: String
    public let recovery: RecoveryAction?
    /// How much this cost the user. Carried rather than worked out downstream: only the
    /// error knows, and this is the last place that still has it.
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

    /// Builds the notice from whatever went wrong.
    ///
    /// Takes `any Error` rather than the product's own failure protocol because the
    /// stages are generic over their thrown type and the compiler cannot narrow it at
    /// the catch. Every error the pipeline can actually see is a ``UttrflowFailure``,
    /// which already carries a sentence written for a user; the fallback exists only so
    /// that an unforeseen one cannot reach the screen as a type name.
    public init(_ error: any Error, transcript: String? = nil) {
        if let failure = error as? any UttrflowFailure {
            self.init(
                message: failure.userMessage, recovery: failure.recovery,
                severity: failure.severity, transcript: transcript)
        } else {
            // Recoverable rather than blocking: an error nobody foresaw is far more
            // likely to be a one-off than a standing obstacle, and guessing the other
            // way would pin a permanent notice to the menu bar over a hiccup.
            self.init(
                message: "Something went wrong. Please try again.", recovery: .retry,
                severity: .recoverable, transcript: transcript)
        }
    }
}

/// What the product finished doing.
public struct DictationOutcome: Sendable, Equatable {
    public let text: String
    public let method: TextInsertionMethod
    /// Which transformer tidied it. Recorded for evaluation; never shown to users.
    public let cleanedBy: TransformerKind
    /// The application the words were typed into, when it could be identified.
    ///
    /// Read from the context the pipeline already gathers for tidying, rather than asked
    /// for a second time: by the time the interface wants to label the dictation the
    /// user has usually moved on, and the answer then would name the wrong app.
    public let insertedInto: String?
    /// That application's bundle identifier, when the context knew it.
    ///
    /// The name is what the interface writes; this is what it can look the app up by.
    /// Two apps can present the same name and one app can change its name between
    /// versions, so a name is a label and an identifier is an identity — and the
    /// identifier is what turns "Claude" into Claude's own icon rather than into
    /// whichever bundle in /Applications happens to be called that.
    public let insertedIntoIdentifier: String?
    /// How long the speaker talked.
    ///
    /// Carried out of the pipeline because it is the one thing about a dictation that
    /// only the pipeline knows and cannot be recovered afterwards. Deliberately NOT a
    /// stage measurement: a stage measurement is a cost Uttrflow imposes, and this is
    /// the user choosing how long to hold the key. Adding it to the latency table
    /// would make a leisurely sentence look like a slow app.
    public let spokenFor: Duration?
    /// Everything Uttrflow changed about what the user said, and why.
    ///
    /// Carried out with the outcome rather than left behind an actor to be fetched,
    /// because it is the evidence for a promise: nothing is applied silently. A change
    /// that reached the screen and did not reach here is a change the user cannot see
    /// and cannot undo, and there would be no way to tell from outside that it had
    /// happened at all.
    public let changes: AppliedChanges

    public init(
        text: String, method: TextInsertionMethod, cleanedBy: TransformerKind,
        insertedInto: String? = nil, insertedIntoIdentifier: String? = nil,
        spokenFor: Duration? = nil, changes: AppliedChanges = .none
    ) {
        self.text = text
        self.method = method
        self.cleanedBy = cleanedBy
        self.insertedInto = insertedInto
        self.insertedIntoIdentifier = insertedIntoIdentifier
        self.spokenFor = spokenFor
        self.changes = changes
    }
}

/// Where a dictation has got to.
///
/// The states the requirements describe in §15, and the only ones the interface has to
/// draw. `failed` is not a fifth kind of progress but a way of leaving, which is why
/// it carries what the user needs to recover rather than an error type.
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
