import Testing
import UttrflowCore

@testable import UttrflowAI

/// A spoken quotation in a query editor is written with the quotes its statement's dialect uses.
@Suite("SQL quoting in a query editor")
struct SQLQuotingTests {
    private static func written(_ spoken: String, after preceding: String? = "select * from users ") -> String
    {
        let app = AppContext(precedingText: preceding)
        let situation = Situation(app: app, insertion: app.insertionPoint, destination: .sqlEditor)
        let pipeline = CleaningPipeline.standard(for: .standard(for: .sqlEditor), situation: situation)
        let text = pipeline.run(Draft(text: spoken)).text
        return text.hasSuffix(".") ? String(text.dropLast()) : text
    }

    // The casing pass, not this one, capitalises the words of a spoken name.
    @Test("a value is in single quotes and an apostrophe inside it is doubled")
    func valueUsesSingleQuotes() {
        #expect(Self.written("where name equals quote o'brien unquote") == "WHERE name = 'o''brien'")
        #expect(Self.written("where city equals quote new york unquote") == "WHERE city = 'New York'")
        #expect(Self.written("where name like quote smith unquote") == "WHERE name LIKE 'smith'")
    }

    @Test("a value opening the piece follows the comparison the field already holds")
    func valueAfterTheCaret() {
        #expect(
            Self.written("quote o'brien unquote", after: "select * from users where name = ") == "'o''brien'")
    }

    @Test("a name stays in the ANSI double quotes when the field shows no other mark")
    func unknownDialectKeepsAnsi() {
        #expect(Self.written("select quote order unquote", after: nil) == "SELECT \"order\"")
        #expect(
            Self.written("select quote order unquote", after: "select \"id\" from \"users\" ")
                == "SELECT \"order\"")
    }

    @Test("a name takes the mark the statement already uses")
    func nameFollowsTheStatement() {
        #expect(
            Self.written("select quote order unquote", after: "select `id` from `users` where ")
                == "SELECT `order`")
        #expect(
            Self.written("select quote order unquote", after: "select [id] from [users] ") == "SELECT [order]"
        )
    }

    @Test("a mixed-case name keeps its case")
    func mixedCaseKept() {
        #expect(
            Self.written("select quote OrderId unquote", after: "select `id` from `users` ")
                == "SELECT `OrderId`")
    }

    @Test("two marks in one statement are no evidence of either")
    func mixedMarksAreUnknown() {
        #expect(
            Self.written("select quote order unquote", after: "select `id`, [name] from users ")
                == "SELECT \"order\"")
    }

    @Test("a quotation that is no comparison's value and has no dialect is left as spoken")
    func undecidedIsLeftAlone() {
        #expect(Self.written("select quote o'brien unquote") == "SELECT \"o'brien\"")
    }
}
