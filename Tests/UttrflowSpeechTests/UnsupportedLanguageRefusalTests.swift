// The rule that refuses speech in a language the product does not transcribe.
import Testing
import UttrflowCore

@testable import UttrflowSpeech

/// A language is refused only when it is certain, outside the transcribed set, and not Hindi heard as Urdu.
@Suite("Refusing a language the product does not transcribe")
struct UnsupportedLanguageRefusalTests {
    static func code(_ identifier: String) throws -> LanguageCode {
        try #require(LanguageCode(identifier))
    }

    static func refused(_ identifier: String, _ probability: Double) throws -> LanguageCode? {
        UnsupportedLanguageRefusal.language(
            heard: try code(identifier), probability: probability, transcribed: LanguageCode.transcribed)
    }

    @Test("refuses a certain language the product does not transcribe", arguments: ["fr", "de", "ja", "es"])
    func refusesCertainForeignSpeech(identifier: String) throws {
        #expect(try Self.refused(identifier, 0.999) == (try Self.code(identifier)))
    }

    @Test("never refuses English or Hindi, however certain", arguments: ["en", "hi"])
    func keepsTranscribedLanguages(identifier: String) throws {
        #expect(try Self.refused(identifier, 1) == nil)
    }

    @Test("never refuses Urdu, which is how the model hears Hindi")
    func keepsUrdu() throws {
        #expect(try Self.refused("ur", 1) == nil)
    }

    @Test("does not refuse a language the model is unsure of")
    func keepsUnsureSpeech() throws {
        #expect(try Self.refused("fr", 0.94) == nil)
        #expect(try Self.refused("fr", UnsupportedLanguageRefusal.minimumProbability) != nil)
    }

    @Test("reads the language a Whisper language token names")
    func readsTokens() throws {
        #expect(UnsupportedLanguageRefusal.language(ofToken: "<|fr|>") == (try Self.code("fr")))
        #expect(UnsupportedLanguageRefusal.language(ofToken: "fr") == nil)
        #expect(UnsupportedLanguageRefusal.language(ofToken: "<||>") == nil)
    }

    @Test("a refusal survives the recogniser's fault wrapping and any other fault is wrapped")
    func wrapping() throws {
        let refusal = SpeechEngineError.unsupportedLanguage(try Self.code("fr"))

        #expect(SpeechEngineError.recognition(failedWith: refusal) == refusal)
        guard
            case .transcriptionFailed = SpeechEngineError.recognition(
                failedWith: SpeechEngineError.nothingHeard)
        else {
            Issue.record("another fault was not wrapped")
            return
        }
    }

    @Test("says the language by name, calmly, and offers nothing to press")
    func notice() throws {
        let refusal = SpeechEngineError.unsupportedLanguage(try Self.code("fr"))

        #expect(refusal.userMessage == "That sounded like French, which Uttrflow can't write yet.")
        #expect(refusal.severity == .informational)
        #expect(refusal.recovery == nil)
        #expect(
            SpeechEngineError.unsupportedLanguage(try Self.code("zz")).userMessage.contains(
                "another language"))
    }
}
