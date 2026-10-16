// Romanised Hindi already in Latin letters when the whole-text passes run, ending on or holding "the" for थे.
import Testing
import UttrflowCore

@testable import UttrflowAI
@testable import UttrflowTestSupport

@Suite("HindiHomographLatin", .bug(id: 7940))
struct HindiHomographLatinTests {
    /// A Hindi sentence ending on "the" with the stop the recogniser wrote, as the message passes see it after romanising.
    static let stopped: [(heard: String, written: String)] = [
        ("usne 15 agast ko 100 rupaye diye the.", "Usne 15 agast ko 100 rupaye diye the."),
        ("Woh kal Delhi gaye the.", "Woh kal Delhi gaye the."),
        ("Hum log wahan gaye the.", "Hum log wahan gaye the."),
        ("Bachche bahar khel rahe the.", "Bachche bahar khel rahe the."),
        ("Woh log kal ghar par the.", "Woh log kal ghar par the."),
        ("Mujhe laga ki tum wahan the.", "Mujhe laga ki tum wahan the."),
        ("Hamare paas kuch nahi the.", "Hamare paas kuch nahi the."),
        ("Ve kal dilli gaye the. Ve kal dilli gaye the.", "Ve kal dilli gaye the. Ve kal dilli gaye the."),
        ("Ve kal dilli gaye the. ve kal dilli gaye the", "Ve kal dilli gaye the. Ve kal dilli gaye the."),
    ]

    @Test("a stop after the Hindi word 'the' stays, with the capital after it", arguments: stopped)
    func hindiStopStays(heard: String, written: String) async throws {
        let out = try await RuleBasedTransformer().transform(
            TransformationRequest(transcription: .fixture(text: heard))
        ).text
        #expect(out == written)
    }

    /// An English sentence ending on "the" is still unfinished: no stop is added or kept.
    @Test(
        "an English sentence ending on 'the' still takes no stop",
        arguments: ["We talked about the.", "He went to the.", "She said that the."]
    )
    func englishArticleTakesNoStop(heard: String) async throws {
        let out = try await RuleBasedTransformer().transform(
            TransformationRequest(transcription: .fixture(text: heard))
        ).text
        #expect(!out.hasSuffix("."))
    }
}
