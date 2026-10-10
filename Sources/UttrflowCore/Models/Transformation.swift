// The request a transformer takes, the result it gives, and how it says whether it can take one.
public import struct Foundation.UUID

/// Everything a transformer needs to clean up one utterance.
public struct TransformationRequest: Sendable, Equatable {
    /// The raw transcript.
    public let transcription: Transcription
    /// What the user is looking at.
    public let context: AppContext
    /// Who is dictating and how they write.
    public let profile: UserProfile
    /// Where the words are going, resolved from the context unless a caller already knows.
    public let situation: Situation
    /// Whether the transcript is the whole message or one piece of it, which decides the passes that run.
    public let scope: CleaningScope
    /// The user's own words this dictation is biased towards, whose written case the rules keep.
    public let vocabulary: [String]
    /// The previous piece of this dictation as heard, read-only context that never reaches the output.
    public let precedingPiece: String?

    /// A request; context and profile default to knowing nothing, and the transcript to being the whole message.
    public init(
        transcription: Transcription,
        context: AppContext = .unknown,
        profile: UserProfile = .default,
        situation: Situation? = nil,
        scope: CleaningScope = .message,
        vocabulary: [String] = [],
        precedingPiece: String? = nil
    ) {
        self.transcription = transcription
        self.context = context
        self.profile = profile
        self.situation = situation ?? SituationResolver.resolve(from: context)
        self.scope = scope
        self.vocabulary = vocabulary
        self.precedingPiece = precedingPiece
    }

    /// The language to route on: what the engine heard, else the user's first preferred language.
    public var effectiveLanguage: LanguageCode? {
        transcription.detectedLanguage?.code ?? profile.preferredLanguages.first
    }
}

/// How much of the message a transcript is. See `Docs/cleanup-design.md` §7.
public enum CleaningScope: Sendable, Equatable {
    /// The whole message: every pass runs, the first word and the final stop included.
    case message
    /// One piece of a longer message: the first word and the final stop wait for the joined whole.
    case piece
}

/// Cleaned-up text, tagged with what produced it.
public struct TransformationResult: Sendable, Equatable {
    /// The cleaned text.
    public let text: String
    /// Which transformer produced this; recorded for evaluation, never shown to users.
    public let producedBy: TransformerKind
    /// What the deterministic steps did on the way, when the transformer keeps a record.
    public let cleaning: CleaningRecord?
    /// The dictionary entries whose spelling the model wrote for a doubtful run, counted used like a correction's.
    public let entriesTaken: [UUID]
    /// Where each pass changed the written words, read from the draft's edit chains; nil where no draft was kept, as on the model path.
    public let changeLedger: [ChangeLedgerEntry]?

    /// A result tagged with its producer and, where one was kept, the record of the steps.
    public init(
        text: String, producedBy: TransformerKind, cleaning: CleaningRecord? = nil,
        entriesTaken: [UUID] = [], changeLedger: [ChangeLedgerEntry]? = nil
    ) {
        self.text = text
        self.producedBy = producedBy
        self.cleaning = cleaning
        self.entriesTaken = entriesTaken
        self.changeLedger = changeLedger
    }

    /// The same result, carrying a record that says what was refused on the way to it.
    public func recording(_ cleaning: CleaningRecord?) -> TransformationResult {
        TransformationResult(
            text: text, producedBy: producedBy, cleaning: cleaning, entriesTaken: entriesTaken,
            changeLedger: changeLedger)
    }
}

/// Whether a transformer can handle a request; a value, not an error, so the preference list routes past it.
public enum TransformerAvailability: Sendable, Equatable {
    /// The engine takes this request.
    case available
    /// The engine works, but not for this language.
    case unsupportedLanguage(LanguageCode)
    /// The engine cannot run at all right now, with the cause retained for the user and Diagnostics.
    case unavailable(reason: TransformerUnavailableReason)

    public var isAvailable: Bool { self == .available }
}

/// Why an engine declined to run, expressed without importing a platform framework into Core.
public enum TransformerUnavailableReason: Sendable, Equatable {
    case appleIntelligenceDisabled
    case modelNotReady
    case deviceNotEligible
    case other(String)

    public var diagnosticDescription: String {
        switch self {
        case .appleIntelligenceDisabled: "Apple Intelligence is switched off"
        case .modelNotReady: "Apple Intelligence is downloading its model"
        case .deviceNotEligible: "This device cannot run Apple Intelligence"
        case .other(let description): description
        }
    }
}
