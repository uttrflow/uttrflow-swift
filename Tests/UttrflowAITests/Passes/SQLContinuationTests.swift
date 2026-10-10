import Testing
import UttrflowCore

@testable import UttrflowAI

/// Words dictated at a caret inside a statement continue it: grammar position outranks prose position.
@Suite("SQL continuation in a query editor")
struct SQLContinuationTests {
    /// The whole cleaning of `spoken` at a caret that follows `preceding`.
    private static func written(_ spoken: String, after preceding: String) -> String {
        let app = AppContext(precedingText: preceding)
        let situation = Situation(app: app, insertion: app.insertionPoint, destination: .sqlEditor)
        let pipeline = CleaningPipeline.standard(for: .standard(for: .sqlEditor), situation: situation)
        return pipeline.run(Draft(text: spoken)).text
    }

    @Test("writes a clause that does not open a statement as notation when a clause is open")
    func continuesWithNotation() {
        for before in ["select * from users ", "select * from users\n", "select *\nfrom users\n"] {
            let text = Self.written("where status equals active", after: before)
            #expect(text.hasPrefix("WHERE status = active"), "\(before.debugDescription) -> \(text)")
        }
        let joined = Self.written(
            "order by name", after: "select * from users u join orders o on u.id = o.user_id ")
        #expect(joined.hasPrefix("ORDER BY name"), "\(joined)")
    }

    @Test("starts mid-statement words in lower case even on a fresh line")
    func firstWordIsNotCapitalised() {
        let text = Self.written("users u where status equals active", after: "select * from\n")
        #expect(text.hasPrefix("users u"), "\(text)")
        let end = Self.written("users u where status equals active", after: "select * from users;\n")
        #expect(end.hasPrefix("Users u"), "\(end)")
    }

    @Test("leaves speech as spoken inside a comment or a string")
    func abstainsInCommentAndString() {
        for before in [
            "select * from users -- ", "select * from users /* ", "select * from users where name = 'bo",
        ] {
            let text = Self.written("where status equals active", after: before)
            #expect(text.hasPrefix("where status equals active"), "\(before.debugDescription) -> \(text)")
        }
    }

    @Test("reads a window that cut the statement as unknown and does not crash")
    func cutWindowIsUnknown() {
        let before = String(repeating: "and age greater than five ", count: 20)
        let text = Self.written("where status equals active", after: before)
        #expect(!text.isEmpty)
    }
}
