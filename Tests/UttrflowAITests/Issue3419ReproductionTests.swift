// Reproduces #3419: a mark or symbol name after a determiner is a noun, not the symbol.
import Testing

@testable import UttrflowAI
@testable import UttrflowCore
@testable import UttrflowTestSupport

/// Issue 3419: "the dot com bubble" stays words rather than becoming "The.com bubble".
@Suite("Issue3419")
struct Issue3419ReproductionTests {
    private func rules(_ spoken: String) async throws -> String {
        try await RuleBasedTransformer().transform(
            TransformationRequest(transcription: .fixture(text: spoken, language: .english))
        ).text
    }

    @Test(
        "a symbol name after a determiner stays a word",
        arguments: [
            ("the dot com bubble burst", "The dot com bubble burst."),
            ("she works at a dot com startup", "She works at a dot com startup."),
            ("the dot net framework is old", "The dot net framework is old."),
            ("the underscore key is broken", "The underscore key is broken."),
            ("use an underscore between the words", "Use an underscore between the words."),
            ("the hundred metre dash is at four", "The hundred metre dash is at four."),
            ("the sign said full stop", "The sign said full stop."),
            ("the phrase question mark is not a question", "The phrase question mark is not a question."),
        ])
    func mentionedSymbolStaysWord(spoken: String, written: String) async throws {
        let result = try await rules(spoken)
        #expect(result == written, "\(result)")
    }

    @Test(
        "a symbol said as one is still written",
        arguments: [
            ("email me at john dot smith at example dot com", "john.smith@example.com"),
            ("the variable is user underscore id", "user_id"),
            ("go to example dot com", "example.com"),
        ])
    func usedSymbolIsWritten(spoken: String, fragment: String) async throws {
        #expect(try await rules(spoken).contains(fragment))
    }
}
