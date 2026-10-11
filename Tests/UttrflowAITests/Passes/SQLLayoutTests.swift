import Testing
import UttrflowCore

@testable import UttrflowAI

/// A spoken multi-clause statement is laid out on clause lines unless the field shows another convention.
@Suite("SQL layout in a query editor")
struct SQLLayoutTests {
    private static func pipeline(after preceding: String?) -> CleaningPipeline {
        let app = AppContext(precedingText: preceding)
        let situation = Situation(app: app, insertion: app.insertionPoint, destination: .sqlEditor)
        return CleaningPipeline.standard(for: .standard(for: .sqlEditor), situation: situation)
    }

    /// The cleaned words without the closing full stop the final-stop pass adds to a statement.
    private static func written(_ spoken: String, after preceding: String?) -> String {
        let text = pipeline(after: preceding).run(Draft(text: spoken)).text
        return text.hasSuffix(".") ? String(text.dropLast()) : text
    }

    @Test("an empty editor lays a multi-clause statement on clause lines with the join indented")
    func emptyEditor() {
        let spoken =
            "select name from users join orders on orders.user_id equals users.id where active equals true"
        for before in [nil, ""] as [String?] {
            #expect(
                Self.written(spoken, after: before)
                    == "SELECT name\nFROM users\n  JOIN orders ON orders.user_id = users.id\nWHERE active = true"
            )
        }
    }

    @Test("a single clause or a fragment stays on one line")
    func singleClauseStaysOnOneLine() {
        #expect(Self.written("select star", after: nil) == "SELECT *")
        #expect(
            Self.written("where status equals active", after: "select * from users ")
                == "WHERE status = active")
    }

    @Test("clauses on one line in the field stay on one line")
    func followsOneLine() {
        let text = Self.written("where active equals true order by name", after: "select name from users ")
        #expect(text == "WHERE active = true ORDER BY name")
    }

    @Test("clauses on their own lines in the field start the next clause on a line with the same indent")
    func followsClauseLines() {
        let before = "select name\nfrom users\n"
        #expect(Self.written("where active equals true", after: before) == "WHERE active = true")
        let midLine = "select name\nfrom users"
        #expect(Self.written("where active equals true", after: midLine) == "\nWHERE active = true")
        let indented = "select name\n  from users"
        #expect(Self.written("where active equals true", after: indented) == "\n  WHERE active = true")
    }

    @Test("spaces and tabs are taken from the text before the caret")
    func detectsIndentCharacter() {
        let tabbed = "\tselect name\n\tfrom users\n\t"
        #expect(
            Self.written("join orders on orders.id equals users.id", after: tabbed)
                == "\tJOIN orders ON orders.id = users.id")
        let spaces = "select name\nfrom users\n    join orders on orders.id = users.id"
        #expect(
            Self.written("where active equals true", after: spaces) == "\nWHERE active = true")
        let continued = Self.written(
            "left join items on items.order_id equals orders.id",
            after: "select name\nfrom users\n    join orders o on o.id = users.id")
        #expect(continued == "\n    LEFT JOIN items ON items.order_id = orders.id")
    }

    @Test("a join takes one indent unit deeper than its clause, in the unit the script uses")
    func joinIndentUnit() {
        let tabbed = "select name\n\tfrom users"
        let spaced = "select name\nfrom users\n"
        #expect(
            Self.written("join orders on orders.id equals users.id", after: tabbed)
                == "\n\t\tJOIN orders ON orders.id = users.id")
        #expect(
            Self.written("join orders on orders.id equals users.id", after: spaced)
                == "  JOIN orders ON orders.id = users.id")
    }

    @Test("a spoken new line is kept and no second break is added")
    func spokenNewLineWins() {
        let text = Self.written("select name new line from users where active equals true", after: nil)
        #expect(text == "SELECT name\nFROM users\nWHERE active = true")
        let before = Self.written("select name from users new line where active equals true", after: nil)
        #expect(before == "SELECT name\nFROM users\nWHERE active = true")
    }

    @Test("a subquery's clauses stay on the line of the statement that holds them")
    func parenthesesAreNotBroken() {
        let inside = Self.written(
            "select user_id from orders where total greater than five",
            after: "select name from users where id in (")
        #expect(inside == "SELECT user_id FROM orders WHERE total > 5")
        let commands = CodeEditorCommandsPass(
            destination: .sqlEditor, evidence: Applicability(cues: [.queryStatement]))
        let spoken = commands.apply(
            Draft(text: "select name from users where id in ( select user_id from orders )"))
        let laid = SQLLayoutPass().apply(spoken)
        #expect(laid.text == "SELECT name\nFROM users\nWHERE id IN ( SELECT user_id FROM orders )")
    }

    @Test("a break is whitespace only: the words written are the words spoken")
    func addsNoClause() {
        let spoken = "select name from users where active equals true"
        let text = Self.written(spoken, after: nil)
        #expect(
            text.split { $0.isWhitespace }.map { $0.lowercased() }
                == "select name from users where active = true".split(separator: " ").map(String.init))
    }

    @Test("cleaning its own output again changes nothing")
    func idempotent() {
        let pipeline = Self.pipeline(after: nil)
        let once = pipeline.run(Draft(text: "select name from users where active equals true"))
        let twice = pipeline.run(once)
        #expect(twice.text == once.text)
        let continuing = Self.pipeline(after: "select name\nfrom users")
        let first = continuing.run(Draft(text: "where active equals true"))
        #expect(continuing.run(first).text == first.text)
    }

    @Test("prose in a query editor is not laid out")
    func proseIsUntouched() {
        let text = Self.written("tell me where the report comes from", after: nil)
        #expect(!text.contains("\n"))
    }
}
