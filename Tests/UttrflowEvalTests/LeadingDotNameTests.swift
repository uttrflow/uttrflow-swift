import Foundation
import Testing
import UttrflowAI
import UttrflowCore

@testable import UttrflowEval

/// A spoken "dot" before a hidden file's name starts that name, so it keeps the space before it.
@Suite("A dot that starts a hidden file's name")
struct LeadingDotNameTests {
    static let cases: [(String, String, String)] = [
        ("open dot gitignore", "codeEditor", "Open .gitignore"),
        ("edit dot env", "codeEditor", "Edit .env"),
        ("cat dot env", "terminal", "cat .env"),
        ("staging dot env", "codeEditor", "Staging .env"),
        ("agents dot md", "codeEditor", "agents.md"),
    ]

    @Test("keeps the space before a hidden file's dot and joins any other name", arguments: cases)
    func writesName(spoken: String, destination: String, expected: String) async throws {
        let record: [String: Any] = [
            "id": "dot-file", "spoken": spoken, "expected": expected, "destination": destination,
        ]
        let data = try JSONSerialization.data(withJSONObject: [record])
        let testCase = try #require(CorpusFile.decode(data, as: .technical).first)
        let result = try await RuleBasedTransformer().transform(testCase.transformationRequest())
        #expect(result.text == expected)
    }
}
