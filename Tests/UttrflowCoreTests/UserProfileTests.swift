// Tests for UserProfile.

import Foundation
import Testing

@testable import UttrflowCore

@Suite("UserProfile")
struct UserProfileTests {
    @Test("defaults to English and nothing else")
    func defaultProfile() {
        #expect(UserProfile.default.preferredLanguages == [.english])
    }

    /// A list with nothing readable left is no preference, so it must not become a different setting.
    @Test(
        "reads languages as saved, an empty list as empty, and a list with nothing readable as the default",
        arguments: [
            (#"["hi", "123", "en"]"#, [LanguageCode.hindi, .english]),
            ("[]", []),
            (#"["123", null]"#, [.english]),
            ("42", [.english]),
        ])
    func unreadableLanguages(saved: String, expected: [LanguageCode]) throws {
        let json = Data(#"{"preferredLanguages": \#(saved)}"#.utf8)
        #expect(try JSONDecoder().decode(UserProfile.self, from: json).preferredLanguages == expected)
    }

    @Test("round-trips a populated profile through Codable")
    func codableRoundTrip() throws {
        let original = UserProfile(preferredLanguages: [.english, .hindi])
        let decoded = try JSONDecoder().decode(UserProfile.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
    }

    @Test("loads a profile saved with the retired self-reported fields and drops them on the next write")
    func retiredFieldsAreIgnored() throws {
        let saved = Data(
            #"""
            {"profession": "surgeon", "preferredLanguages": ["hi", "en"], "technicalDomains": ["SQL"],
             "preferredWritingStyle": "Concise", "vocabulary": ["Kubernetes"]}
            """#.utf8)
        let loaded = try JSONDecoder().decode(UserProfile.self, from: saved)
        #expect(loaded == UserProfile(preferredLanguages: [.hindi, .english]))

        let written = try JSONSerialization.jsonObject(with: JSONEncoder().encode(loaded)) as? [String: Any]
        #expect(written.map { Set($0.keys) } == ["preferredLanguages", "pauses"])
    }
}
