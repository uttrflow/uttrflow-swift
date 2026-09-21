// What recognition may hear a dictation's pieces as, read off the languages the user speaks.

/// How each piece of a dictation is given its language. See `Docs/speech-engines.md`.
public enum ListeningLanguages: Sendable, Equatable {
    /// Every piece is decoded in this language, the only one the user speaks that the product transcribes.
    case only(LanguageCode)
    /// Every piece detects its own language among the product's, since the user switches between them.
    case eachPiece
    /// The first piece detects and every later piece is held to it, for a profile that has not said it speaks Hindi.
    case firstPiece

    /// The listening a profile asks for; English alone is also the default, so it cannot narrow detection.
    public init(profile: UserProfile) {
        let spoken = LanguageCode.transcribed.filter(profile.preferredLanguages.contains)
        guard spoken.contains(.hindi) else {
            self = .firstPiece
            return
        }
        self = spoken.count == 1 ? .only(.hindi) : .eachPiece
    }

    /// The hint for the next piece, given the language the dictation's first piece was heard in.
    public func hint(afterFirstPiece heard: LanguageCode?) -> LanguageCode? {
        switch self {
        case .only(let language): language
        case .eachPiece: nil
        case .firstPiece: heard
        }
    }
}
