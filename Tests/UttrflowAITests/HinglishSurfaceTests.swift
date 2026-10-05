// Romanised and mixed Hindi on the rules-only path: spacing, casing and sentence marks.
import Testing

@testable import UttrflowAI
@testable import UttrflowCore
@testable import UttrflowTestSupport

@Suite("HinglishSurface")
struct HinglishSurfaceTests {
    @Test(
        "spaces, cases and stops romanised and mixed Hindi as it does English",
        arguments: [
            ("train late है। मैं बाद में call करूंगा", "Train late hai. Main baad mein call karunga."),
            ("theek hai। main aata hoon", "Theek hai. Main aata hoon."),
            ("मैंने कहा   कि ठीक है", "Maine kaha ki thik hai."),
            ("office पहुँचकर call करो।।", "Office pahunchakar call karo."),
            ("हाँ, मैं आ रहा हूँ।", "Haan, main aa raha hoon."),
            ("मैं ठीक हूँ ।", "Main thik hoon."),
            ("मैं ठीक हूँ।ठीक है", "Main thik hoon. Thik hai."),
            ("kya tum aaoge? haan main aaunga", "Kya tum aaoge? Haan main aaunga."),
            ("देखो! क्या हुआ", "Dekho! Kya hua?"),
            ("देखो!। क्या हुआ", "Dekho! Kya hua?"),
            ("मैं Delhi जा रहा हूँ", "Main Delhi ja raha hoon."),
            ("मैं iPhone use करता हूँ", "Main iPhone use karta hoon."),
        ])
    func surface(spoken: String, written: String) async throws {
        let out = try await RuleBasedTransformer().transform(
            TransformationRequest(transcription: .fixture(text: spoken, language: .hindi))
        ).text
        #expect(out == written)
        #expect(LatinScript.isLatin(out))
    }
}
