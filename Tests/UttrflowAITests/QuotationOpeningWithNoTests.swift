import Testing

@testable import UttrflowAI
@testable import UttrflowCore
@testable import UttrflowTestSupport

/// A spoken quotation keeps its words whatever its first word is.
@Suite("QuotationOpeningWithNo")
struct QuotationOpeningWithNoTests {
    private func request(_ text: String) -> TransformationRequest {
        TransformationRequest(transcription: .fixture(text: text, language: .english))
    }

    @Test(
        "wraps a quotation whose first word is a determiner",
        arguments: [
            ("she answered open quote no way close quote", "She answered \"no way.\""),
            (
                "they said open quote no problem close quote and smiled",
                "They said \"no problem\" and smiled."
            ),
            ("the sign says open quote no parking close quote", "The sign says \"no parking.\""),
            ("he replied open quote no close quote and left", "He replied \"no\" and left."),
            ("she said open quote no close quote", "She said \"no.\""),
            ("she said open quote the end close quote", "She said \"the end.\""),
            ("she said open quote yes close quote", "She said \"yes.\""),
        ])
    func wrapsTheQuotation(spoken: String, expected: String) async throws {
        let text = try await RuleBasedTransformer().transform(request(spoken)).text
        #expect(text == expected)
    }
}
