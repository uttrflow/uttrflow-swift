/// Who the user is and how they write; only ``preferredLanguages`` is populated, and nothing is uploaded.
public struct UserProfile: Sendable, Equatable, Codable {
    /// What the user does for a living, when they say.
    public var profession: String?
    /// Languages in order of preference; the first is the routing fallback.
    public var preferredLanguages: [LanguageCode]
    /// Fields whose jargon the transformer may meet.
    public var technicalDomains: [String]
    /// How the user likes their prose, when they say.
    public var preferredWritingStyle: String?
    /// Terms the user says often that engines routinely mis-transcribe.
    public var vocabulary: [String]

    /// A profile; every field defaults to knowing nothing but English.
    public init(
        profession: String? = nil,
        preferredLanguages: [LanguageCode] = [.english],
        technicalDomains: [String] = [],
        preferredWritingStyle: String? = nil,
        vocabulary: [String] = []
    ) {
        self.profession = profession
        self.preferredLanguages = preferredLanguages
        self.technicalDomains = technicalDomains
        self.preferredWritingStyle = preferredWritingStyle
        self.vocabulary = vocabulary
    }

    /// The profile a user has before they configure anything.
    public static let `default` = UserProfile()
}
