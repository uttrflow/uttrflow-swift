/// Everything a transformer needs to clean up one utterance.
public struct TransformationRequest: Sendable, Equatable {
    public let transcription: Transcription
    public let context: AppContext
    public let profile: UserProfile
    /// Where the words are going, resolved from the context unless a caller already knows.
    public let situation: Situation

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

    /// The language to route on: what the engine heard, falling back to the user's
    /// first preferred language when the engine did not report one.
    public var effectiveLanguage: LanguageCode? {
        transcription.detectedLanguage?.code ?? profile.preferredLanguages.first
    }
}

/// Cleaned-up text, tagged with what produced it.
public struct TransformationResult: Sendable, Equatable {
    public let text: String
    /// Which transformer produced this. Recorded for evaluation; never shown to users.
    public let producedBy: TransformerKind

    public init(text: String, producedBy: TransformerKind) {
        self.text = text
        self.producedBy = producedBy
    }
}

/// Whether a transformer can handle a particular request.
///
/// Modelling "cannot do Hindi" as a value rather than an error lets the preference
/// list route around a limitation without treating it as a failure.
public enum TransformerAvailability: Sendable, Equatable {
    case available
    /// The engine works, but not for this language.
    case unsupportedLanguage(LanguageCode)
    /// The engine cannot run at all right now — model missing, hardware unsupported.
    case unavailable(reason: String)

    public var isAvailable: Bool { self == .available }
}
