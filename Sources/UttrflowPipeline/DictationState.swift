// Where a dictation has got to, how it ended, and what went wrong.
public import Foundation
public import UttrflowCore

/// Something that went wrong, carrying the transcript so the user's words stay reachable (§19).
public struct DictationFailure: Sendable, Equatable {
    public let message: String
    public let recovery: RecoveryAction?
    /// How much this cost the user; carried because only the error knows and this is the last place with it.
    public let severity: FailureSeverity
    /// What the user said, when there was anything to salvage.
    public let transcript: String?
    /// Whether the words were meant for a field that hides what is typed, so they are kept nowhere.
    public let intoSecureField: Bool
    /// Which recogniser failed, when speech preparation or transcription failed.
    public let speechEngineKind: SpeechEngineKind?
    /// The original typed speech failure, when the source error is a speech-engine error.
    public let speechEngineError: SpeechEngineError?
    /// The kept recording `.retryFromRecording` runs again, so the notice's button retries it directly.
    public let keptRecording: UUID?

    public init(
        message: String, recovery: RecoveryAction?, severity: FailureSeverity,
        transcript: String? = nil, intoSecureField: Bool = false,
        speechEngineKind: SpeechEngineKind? = nil, speechEngineError: SpeechEngineError? = nil,
        keptRecording: UUID? = nil
    ) {
        self.message = message
        self.recovery = recovery
        self.severity = severity
        self.transcript = transcript
        self.intoSecureField = intoSecureField
        self.speechEngineKind = speechEngineKind
        self.speechEngineError = speechEngineError
        self.keptRecording = keptRecording
    }

    /// The salvaged words Uttrflow may keep or show, which is none for a secure field or a credential.
    public var wordsToKeep: String? {
        transcript.flatMap { KeptWords.of($0, intoSecureField: intoSecureField) }
    }

    /// Builds the notice from any error; the fallback keeps an unforeseen one off the screen as a type name.
    public init(
        _ error: any Error, transcript: String? = nil,
        speechEngineKind: SpeechEngineKind? = nil
    ) {
        if let failure = error as? any UttrflowFailure {
            self.init(
                message: failure.userMessage, recovery: failure.recovery,
                severity: failure.severity, transcript: transcript,
                speechEngineKind: speechEngineKind, speechEngineError: error as? SpeechEngineError)
        } else {
            // Recoverable rather than blocking: an unforeseen error is far more likely a one-off.
            self.init(
                message: "Something went wrong. Please try again.", recovery: .retry,
                severity: .recoverable, transcript: transcript, speechEngineKind: speechEngineKind)
        }
    }

    /// A dictation tried while the speech model loads: nothing went wrong, it is only not ready.
    public static let stillLoading = DictationFailure(
        message: SpeechModelLoad.refusal, recovery: nil, severity: .informational)

    /// The same failure offering a different next step.
    public func offering(_ recovery: RecoveryAction?) -> DictationFailure {
        DictationFailure(
            message: message, recovery: recovery, severity: severity, transcript: transcript,
            intoSecureField: intoSecureField, speechEngineKind: speechEngineKind,
            speechEngineError: speechEngineError, keptRecording: keptRecording)
    }

    /// The same failure offering to run the kept recording again.
    public func offeringRetry(of recording: UUID) -> DictationFailure {
        DictationFailure(
            message: message, recovery: .retryFromRecording, severity: severity, transcript: transcript,
            intoSecureField: intoSecureField, speechEngineKind: speechEngineKind,
            speechEngineError: speechEngineError, keptRecording: recording)
    }

    /// The same failure, marked as meant for a field that hides what is typed.
    public func markingSecure(_ secure: Bool) -> DictationFailure {
        let cannotCopySecureTranscript = secure && recovery == .copyTranscript
        return DictationFailure(
            message: cannotCopySecureTranscript
                ? "The secure field didn't accept the text. The clipboard is unchanged, and the words were not kept."
                : message,
            recovery: cannotCopySecureTranscript ? nil : recovery,
            severity: severity, transcript: transcript,
            intoSecureField: secure, speechEngineKind: speechEngineKind,
            speechEngineError: speechEngineError, keptRecording: keptRecording)
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
    /// Dictionary corrections and snippet firings carried with the inserted dictation.
    public let changes: AppliedChanges
    /// Whether this comes from a kept recording rather than the microphone, and is copied, not typed.
    public let isFromRecording: Bool
    /// Whether the words were seen to reach the caret, which is what the tick is allowed to claim.
    public let arrival: InsertionArrival
    /// Whether the words went into a field that hides what is typed, so no history or clip keeps them.
    public let intoSecureField: Bool
    /// Pieces of speech that decoded to no words twice and are missing from the text; zero when nothing is.
    public let missedPieces: Int
    /// Availability causes that made this successful dictation use a lower-priority engine.
    public let unavailableEngines: [CleaningRecord.UnavailableEngine]
    /// Which written words the recogniser doubted, as positions only; memory only, never persisted.
    public let doubtful: DoubtfulWordsOutcome
    /// Why the wait after key-up runs past its target; `nil` when it keeps to it or is untimed.
    public let slowCause: SlowDictationCause?

    public init(
        text: String, method: TextInsertionMethod, cleanedBy: TransformerKind,
        insertedInto: String? = nil, insertedIntoIdentifier: String? = nil,
        spokenFor: Duration? = nil, changes: AppliedChanges = .none, fromRecording: Bool = false,
        arrival: InsertionArrival = .notReported, intoSecureField: Bool = false, missedPieces: Int = 0,
        unavailableEngines: [CleaningRecord.UnavailableEngine] = [],
        doubtful: DoubtfulWordsOutcome = .notAvailable, slowCause: SlowDictationCause? = nil
    ) {
        self.text = text
        self.method = method
        self.cleanedBy = cleanedBy
        self.insertedInto = insertedInto
        self.insertedIntoIdentifier = insertedIntoIdentifier
        self.spokenFor = spokenFor
        self.changes = changes
        self.isFromRecording = fromRecording
        self.arrival = arrival
        self.intoSecureField = intoSecureField
        self.missedPieces = missedPieces
        self.unavailableEngines = unavailableEngines
        self.doubtful = doubtful
        self.slowCause = slowCause
    }

    /// The words Uttrflow may keep or show, which is none for a secure field or a credential.
    public var wordsToKeep: String? { KeptWords.of(text, intoSecureField: intoSecureField) }
}

/// The one gate deciding whether dictated words may outlive their insertion. See Docs/clipboard-secrets.md.
enum KeptWords {
    /// The words, or nil when they went into a secure field or are shaped like a credential.
    static func of(_ words: String, intoSecureField: Bool) -> String? {
        intoSecureField || SecretShapes.matches(words) ? nil : words
    }
}

/// A recording the user cancelled while it was long enough to be worth saying so. See Docs/recordings.md.
public struct DictationDiscard: Sendable, Equatable {
    /// How long the microphone was open before the cancel.
    public let spokenFor: Duration
    /// The audio kept for a Restore during ``DictationPipeline/restoreWindow``; absent for a secure field.
    public let keptRecording: UUID?

    public init(spokenFor: Duration, keptRecording: UUID?) {
        self.spokenFor = spokenFor
        self.keptRecording = keptRecording
    }
}

/// Where a dictation has got to (§15); `failed` is a way of leaving that carries what recovery needs.
public enum DictationState: Sendable, Equatable {
    case idle
    case recording
    case transcribing
    case tidying
    /// The words have been handed to the app, named when known, which has not yet shown them.
    case inserting(into: String?)
    case inserted(DictationOutcome)
    case failed(DictationFailure)
    /// Cancelled while recording, past ``DictationPipeline/restoreThreshold``; nothing was typed.
    case discarded(DictationDiscard)

    /// Whether a new dictation can begin.
    public var isBusy: Bool {
        switch self {
        case .recording, .transcribing, .tidying, .inserting: true
        case .idle, .inserted, .failed, .discarded: false
        }
    }

    /// Whether the dictation has reached an outcome.
    public var hasEnded: Bool {
        switch self {
        case .inserted, .failed: true
        case .idle, .recording, .transcribing, .tidying, .inserting, .discarded: false
        }
    }

    /// Whether the microphone is live. Drives the recording indicator.
    public var isListening: Bool { self == .recording }
}
