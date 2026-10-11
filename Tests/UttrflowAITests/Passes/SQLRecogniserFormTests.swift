import Foundation
import Testing
import UttrflowCore
import UttrflowEval

@testable import UttrflowAI

/// A statement the recogniser cased and punctuated is written as the same SQL as the bare words.
@Suite("SQL notation from recogniser-style text")
struct SQLRecogniserFormTests {
    private static let statements = EvaluationCorpus.all.filter { $0.id.hasPrefix("sql-statement-") }

    /// Words a recogniser pauses before in a statement.
    private static let clauseOpeners: Set<String> = [
        "from", "where", "join", "inner", "left", "order", "group", "having", "limit",
    ]

    /// The words as a recogniser writes them: a capital at the start, a comma or a stop at each pause, a stop at the end.
    static func recogniserForm(_ spoken: String, stop: String) -> String {
        var words = spoken.split(separator: " ").map(String.init)
        for index in words.indices.dropFirst() where clauseOpeners.contains(words[index]) {
            if words[index - 1] == "left" || words[index - 1] == "inner" { continue }
            words[index - 1] += stop
            if stop == "." { words[index] = words[index].prefix(1).uppercased() + words[index].dropFirst() }
        }
        words[0] = words[0].prefix(1).uppercased() + words[0].dropFirst()
        words[words.count - 1] += "."
        return words.joined(separator: " ")
    }

    private func written(_ testCase: EvaluationCase, spoken: String) async throws -> String {
        let base = testCase.transformationRequest()
        let request = TransformationRequest(
            transcription: Transcription(
                text: spoken, detectedLanguage: base.transcription.detectedLanguage, segments: []),
            context: base.context, situation: base.situation)
        return try await RuleBasedTransformer().transform(request).text
    }

    @Test("a comma at each pause changes nothing in the statement")
    func commaPauses() async throws {
        for testCase in Self.statements {
            let output = try await written(testCase, spoken: Self.recogniserForm(testCase.spoken, stop: ","))
            #expect(output == testCase.expected, "\(testCase.id)")
        }
    }

    @Test("a stop and a capital at each pause change nothing in the statement")
    func stopPauses() async throws {
        for testCase in Self.statements {
            let output = try await written(testCase, spoken: Self.recogniserForm(testCase.spoken, stop: "."))
            #expect(output == testCase.expected, "\(testCase.id)")
        }
    }

    @Test("keeps an unspaced token and a said comma, and writes no stop the recogniser added")
    func keepsTokens() async throws {
        let base = try #require(Self.statements.first)
        let said = try await written(base, spoken: "Select name comma email, from customers.")
        #expect(said == "SELECT name, email FROM customers")
        let tokens = try await written(base, spoken: "Select * from users where created_at > 2026-01-01")
        #expect(tokens == "SELECT * FROM users WHERE created_at > 2026-01-01")
    }
}
