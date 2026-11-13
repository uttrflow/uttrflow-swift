import Foundation
import Testing
import UttrflowAI
import UttrflowCore

@testable import UttrflowEval

/// JSON values said in one go: a cut inside one reads a value with no key before it, so these stay out of the seam corpus.
@Suite("JSON notation said whole")
struct JSONNotationWholeTests {
    /// What is said, what a JSON file receives, and the text before the caret.
    static let cases: [(String, String, String)] = [
        ("name colon sam", "\"name\": \"sam\"", "{\n  "),
        ("active colon true", "\"active\": true", "{\n  "),
        ("enabled colon false", "\"enabled\": false", "{\n  "),
        ("id colon one two three", "\"id\": 123", "{\n  "),
        ("version colon one point two point three", "\"version\": \"1.2.3\"", "{\n  "),
        ("first name colon sam", "\"first name\": \"sam\"", "{\n  "),
        ("title colon the quick brown fox", "\"title\": \"the quick brown fox\"", "{\n  "),
        ("host colon localhost", "\"host\": \"localhost\"", "{\n  "),
        ("open brace name colon sam close brace", "{\"name\": \"sam\"}", "[\n  "),
        (
            "server colon open brace host colon localhost comma port colon eight zero eight zero close brace",
            "\"server\": {\"host\": \"localhost\", \"port\": 8080}", "{\n  "
        ),
        (
            "users colon open bracket open brace id colon one close brace comma open brace id colon two close brace close bracket",
            "\"users\": [{\"id\": 1}, {\"id\": 2}]", "{\n  "
        ),
        ("debug colon true close brace", "\"debug\": true}", "{\n  \"name\": \"notes\",\n  "),
        ("mode colon dark", "\"mode\": \"dark\"", "{\n  \"name\": \"notes\",\n  "),
        ("answer colon true story", "\"answer\": \"true story\"", "{\n  "),
        ("label colon thirty days", "\"label\": \"30 days\"", "{\n  "),
    ]

    private func evaluationCase(
        _ spoken: String, _ expected: String, _ preceding: String
    ) throws -> EvaluationCase {
        let record: [String: Any] = [
            "id": "json-whole", "spoken": spoken, "expected": expected, "expectedExact": expected,
            "destination": "codeEditor",
            "context": [
                "applicationName": "Visual Studio Code", "bundleIdentifier": "com.microsoft.VSCode",
                "documentName": "config.json", "precedingText": preceding,
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: [record])
        return try #require(CorpusFile.decode(data, as: .technical).first)
    }

    @Test("a JSON file receives quoted keys and strings, bare numbers and literals", arguments: cases)
    func writesJSON(spoken: String, expected: String, preceding: String) async throws {
        let testCase = try evaluationCase(spoken, expected, preceding)
        let result = try await RuleBasedTransformer().transform(testCase.transformationRequest())
        #expect(result.text == expected)
    }
}
