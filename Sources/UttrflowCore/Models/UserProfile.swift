/// Who the user is and how they write.
///
/// V1 populates only ``preferredLanguages``; the remaining fields exist so that
/// personalisation can be switched on later without reshaping the transformer API.
/// Nothing here is uploaded anywhere.
public struct UserProfile: Sendable, Equatable, Codable {
    public var profession: String?
    public var preferredLanguages: [LanguageCode]
    public var technicalDomains: [String]
    public var preferredWritingStyle: String?
    /// Terms the user says often that engines routinely mis-transcribe.
    public var vocabulary: [String]

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
