// Hindi sentences holding words whose romanised spelling is also an English function word.
import Testing
import UttrflowCore

@testable import UttrflowAI
@testable import UttrflowTestSupport

@Suite("HindiHomograph")
struct HindiHomographTests {
    /// Mid- or end-sentence the/to/do/main/hai/par homographs, none a question; "दो" as two is left out as a digit.
    static let statements: [String] = [
        "वो कल यहाँ थे",
        "हम सब घर पर थे",
        "बच्चे बाहर खेल रहे थे",
        "आप भी वहाँ थे",
        "वो दोनों साथ थे",
        "मैं आ रहा हूँ तो",
        "अगर तुम चलो तो",
        "ठीक है तो",
        "तो फिर मिलते हैं",
        "तो हम कल चलेंगे",
        "मुझे दो रोटी दो",
        "उसको पानी दो",
        "वो घर पर ही थे",
        "वो दो दो करके आए",
        "मुझे थोड़ा समय दो",
        "मैं घर जा रहा हूँ",
        "मैं ठीक हूँ",
        "आज मैं नहीं आऊँगा",
        "मैं भी चलूँगा",
        "कल मैं बाज़ार गया था",
        "किताब मेज़ पर है",
        "वो छत पर है",
        "मैंने कहा था पर वो नहीं माने",
        "सब ठीक है",
        "खाना तैयार है",
        "वो दफ़्तर में है",
        "बारिश हो रही है",
        "मैं तो वहाँ थे ही नहीं",
        "तुम रुको तो",
        "हम लोग कल वहीं थे",
        "मैं सोच रहा था कि तुम आओगे तो",
        "पैसे मुझे दो",
    ]

    @Test(
        "a Hindi statement with an English homograph is only capitalised and stopped",
        arguments: statements
    )
    func statementKeepsItsWords(spoken: String) async throws {
        let out = try await RuleBasedTransformer().transform(
            TransformationRequest(transcription: .fixture(text: spoken, language: .hindi))
        ).text
        let romanised = Romaniser.romanised(spoken)
        let expected = romanised.prefix(1).uppercased() + romanised.dropFirst() + "."
        #expect(out == expected)
    }

    @Test("the corpus holds at least 30 sentences")
    func corpusSize() {
        #expect(Self.statements.count >= 30)
    }
}
