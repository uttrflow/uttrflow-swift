import Foundation
import Testing

@testable import UttrflowCore

@Suite("UserProfile")
struct UserProfileTests {
    @Test("defaults to English and nothing else")
    func defaultProfile() {
        #expect(UserProfile.default.preferredLanguages == [.english])
        #expect(UserProfile.default.profession == nil)
        #expect(UserProfile.default.technicalDomains.isEmpty)
        #expect(UserProfile.default.preferredWritingStyle == nil)
        #expect(UserProfile.default.vocabulary.isEmpty)
    }

    @Test("round-trips a fully populated profile through Codable")
    func codableRoundTrip() throws {
        let original = UserProfile(
            profession: "Software Engineer",
            preferredLanguages: [.english, .hindi],
            technicalDomains: ["Python", "SQL"],
            preferredWritingStyle: "Concise",
            vocabulary: ["Kubernetes"]
        )
        let decoded = try JSONDecoder().decode(UserProfile.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
    }
}
