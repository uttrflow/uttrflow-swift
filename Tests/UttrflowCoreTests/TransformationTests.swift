import Foundation
import Testing

@testable import UttrflowCore
@testable import UttrflowTestSupport

@Suite("TransformationRequest")
struct TransformationRequestTests {
    @Test("routes on the language the engine actually detected")
    func prefersDetectedLanguage() {
        let request = TransformationRequest(
            transcription: .fixture(language: .hindi),
            profile: UserProfile(preferredLanguages: [.english])
        )
        #expect(request.effectiveLanguage == .hindi)
    }

    @Test("falls back to the user's first language when detection reports nothing")
    func fallsBackToProfileLanguage() {
        let request = TransformationRequest(
            transcription: .fixture(language: nil),
            profile: UserProfile(preferredLanguages: [.hindi, .english])
        )
        #expect(request.effectiveLanguage == .hindi)
    }

    @Test("has no language to route on when neither source supplies one")
    func noLanguageAtAll() {
        let request = TransformationRequest(
            transcription: .fixture(language: nil),
            profile: UserProfile(preferredLanguages: [])
        )
        #expect(request.effectiveLanguage == nil)
    }

    @Test("defaults to an unknown context and a default profile")
    func defaults() {
        let request = TransformationRequest(transcription: .fixture())
        #expect(request.context == .unknown)
        #expect(request.profile == .default)
    }
}

@Suite("TransformerAvailability")
struct TransformerAvailabilityTests {
    @Test("treats only the available case as available")
    func isAvailable() {
        #expect(TransformerAvailability.available.isAvailable)
        #expect(!TransformerAvailability.unsupportedLanguage(.hindi).isAvailable)
        #expect(!TransformerAvailability.unavailable(reason: "no model").isAvailable)
    }

    @Test("distinguishes which language is unsupported")
    func carriesTheUnsupportedLanguage() {
        #expect(
            TransformerAvailability.unsupportedLanguage(.hindi)
                != .unsupportedLanguage(.english)
        )
    }
}

@Suite("TransformationResult")
struct TransformationResultTests {
    @Test("records which engine produced the text")
    func attributesOutput() {
        let result = TransformationResult(text: "Hello.", producedBy: .rules)
        #expect(result.text == "Hello.")
        #expect(result.producedBy == .rules)
        #expect(result != TransformationResult(text: "Hello.", producedBy: .localModel))
    }
}

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
