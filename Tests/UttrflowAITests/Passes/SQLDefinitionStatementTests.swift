import Foundation
import Testing
import UttrflowCore

@testable import UttrflowAI

/// A schema statement dictated into a query editor is written as SQL, as a query is.
@Suite("SQL definition statements in a query editor")
struct SQLDefinitionStatementTests {
    private static let context = AppContext(
        applicationName: "TablePlus", bundleIdentifier: "com.tinyapp.TablePlus", documentName: "shop.sql")

    private static func written(_ spoken: String) async throws -> String {
        let situation = Situation(app: context, insertion: context.insertionPoint, destination: .sqlEditor)
        let request = TransformationRequest(
            transcription: .fixture(text: spoken, language: .english), context: context,
            situation: situation)
        return try await RuleBasedTransformer().transform(request).text
    }

    @Test("writes a statement that opens with create, alter, drop, truncate or with as notation")
    func writesNotation() async throws {
        let spoken = [
            "create table notes open paren id serial primary key comma body text not null close paren",
            "alter table users drop column legacy underscore flag",
            "drop index if exists idx underscore users underscore email",
            "truncate table sessions",
            "with recent as open paren select star from orders close paren select star from recent",
        ]
        for text in spoken {
            let output = try await Self.written(text)
            #expect(!output.hasSuffix("."), "\(text) -> \(output)")
            #expect(!output.lowercased().contains("paren"), "\(text) -> \(output)")
            #expect(!output.contains(" comma"), "\(text) -> \(output)")
            #expect(!output.contains("underscore"), "\(text) -> \(output)")
        }
        #expect(try await Self.written(spoken[1]).contains("legacy_flag"))
        #expect(try await Self.written(spoken[2]).contains("idx_users_email"))
        #expect(try await Self.written(spoken[4]).contains("AS (SELECT * FROM orders) SELECT"))
        #expect(
            try await Self.written(spoken[0]).lowercased().contains(
                "(id serial primary key, body text not null)"))
    }

    @Test("keeps a sentence that begins with drop or with as a sentence")
    func keepsProse() async throws {
        for text in [
            "with the new schema we can drop the old table", "drop me a line when the table is ready",
        ] {
            let output = try await Self.written(text)
            #expect(output.hasSuffix("."), "\(output)")
        }
    }
}
