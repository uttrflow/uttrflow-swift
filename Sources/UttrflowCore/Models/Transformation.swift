// The request a transformer takes, the result it gives, and how it says whether it can take one.

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

    /// A request; context and profile default to knowing nothing.
    public init(
        transcription: Transcription,
        context: AppContext = .unknown,
        profile: UserProfile = .default,
        situation: Situation? = nil
    ) {
        self.transcription = transcription
        self.context = context
        self.profile = profile
        self.situation = situation ?? SituationResolver.resolve(from: context)
    }

    /// The language to route on: what the engine heard, else the user's first preferred language.
    public var effectiveLanguage: LanguageCode? {
        transcription.detectedLanguage?.code ?? profile.preferredLanguages.first
    }
}

/// Cleaned-up text, tagged with what produced it.
public struct TransformationResult: Sendable, Equatable {
    /// The cleaned text.
    public let text: String
    /// Which transformer produced this; recorded for evaluation, never shown to users.
    public let producedBy: TransformerKind

    /// A result tagged with its producer.
    public init(text: String, producedBy: TransformerKind) {
        self.text = text
        self.producedBy = producedBy
    }
}

/// Whether a transformer can handle a request; a value, not an error, so the preference list routes past it.
public enum TransformerAvailability: Sendable, Equatable {
    /// The engine takes this request.
    case available
    /// The engine works, but not for this language.
    case unsupportedLanguage(LanguageCode)
    /// The engine cannot run at all right now — model missing, hardware unsupported.
    case unavailable(reason: String)

    public var isAvailable: Bool { self == .available }
}
