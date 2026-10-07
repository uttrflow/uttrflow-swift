/// The user's settings profile: the languages they speak, and nothing is uploaded.
public struct UserProfile: Sendable, Equatable, Codable {
    /// Languages in order of preference; the first is the routing fallback.
    public var preferredLanguages: [LanguageCode]

    /// How long the person pauses while speaking.
    public var pauses: PauseLength

    /// A profile; it defaults to knowing nothing but English, spoken with usual pauses.
    public init(preferredLanguages: [LanguageCode] = [.english], pauses: PauseLength = .usual) {
        self.preferredLanguages = preferredLanguages
        self.pauses = pauses
    }

    /// The profile a user has before they configure anything.
    public static let `default` = UserProfile()
}

extension UserProfile {
    /// Keeps readable languages when neighbouring saved values cannot be decoded; keys it does not know are ignored.
    public init(from decoder: any Decoder) throws {
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
            self = .default
            return
        }
        self.init(
            preferredLanguages: container.readableElements(
                of: LanguageCode.self, forKey: .preferredLanguages, fallback: Self.default.preferredLanguages),
            pauses: (try? container.decodeIfPresent(PauseLength.self, forKey: .pauses)) ?? Self.default.pauses
        )
    }
}
