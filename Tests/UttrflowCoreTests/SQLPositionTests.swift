import Testing

@testable import UttrflowCore

/// The grammar position of the caret in a statement, read from invented preceding text.
@Suite("SQL position")
struct SQLPositionTests {
    /// One invented preceding text and what the position must say of it.
    struct Case: Sendable, CustomTestStringConvertible {
        let text: String
        let clause: SQLPosition.Clause?
        var keywordCase: SQLPosition.KeywordCase = .unknown
        var tables: [String] = []
        var aliases: [String] = []
        var inString = false
        var inComment = false
        var testDescription: String { text }
    }

    static let cases: [Case] = [
        Case(text: "", clause: nil),
        Case(text: "   \n", clause: nil),
        Case(text: "hello there ", clause: nil),
        Case(text: "select ", clause: .select, keywordCase: .lower),
        Case(text: "SELECT * ", clause: .select, keywordCase: .upper),
        Case(text: "select * from ", clause: .from, keywordCase: .lower),
        Case(text: "select * from users ", clause: .from, keywordCase: .lower, tables: ["users"]),
        Case(text: "SELECT * FROM users ", clause: .from, keywordCase: .upper, tables: ["users"]),
        Case(text: "SELECT * from users ", clause: .from, keywordCase: .mixed, tables: ["users"]),
        Case(
            text: "select * from users u ", clause: .from, keywordCase: .lower, tables: ["users"],
            aliases: ["u"]),
        Case(
            text: "select * from users as u ", clause: .from, keywordCase: .lower, tables: ["users"],
            aliases: ["u"]),
        Case(
            text: "select * from public.users ", clause: .from, keywordCase: .lower,
            tables: ["public.users"]),
        Case(
            text: "select * from users where ", clause: .where, keywordCase: .lower, tables: ["users"]),
        Case(
            text: "select * from users where id = 5 and ", clause: .where, keywordCase: .lower,
            tables: ["users"]),
        Case(
            text: "select * from users u join orders o ", clause: .join, keywordCase: .lower,
            tables: ["users", "orders"], aliases: ["u", "o"]),
        Case(
            text: "select * from users u left join orders o on ", clause: .on, keywordCase: .lower,
            tables: ["users", "orders"], aliases: ["u", "o"]),
        Case(
            text: "select * from users u join orders o on u.id = o.user_id where ", clause: .where,
            keywordCase: .lower, tables: ["users", "orders"], aliases: ["u", "o"]),
        Case(
            text: "select a, count(*) from t group by ", clause: .groupBy, keywordCase: .lower,
            tables: ["t"]),
        Case(text: "select a from t group by a having ", clause: .having, keywordCase: .lower, tables: ["t"]),
        Case(
            text: "select a from t order by a ", clause: .orderBy, keywordCase: .lower, tables: ["t"]),
        Case(text: "select a from t limit ", clause: .limit, keywordCase: .lower, tables: ["t"]),
        Case(text: "select a from a, b ", clause: .from, keywordCase: .lower, tables: ["a", "b"]),
        Case(
            text: "insert into items ", clause: .insertInto, keywordCase: .lower, tables: ["items"]),
        Case(text: "insert into items values ", clause: .values, keywordCase: .lower, tables: ["items"]),
        Case(text: "update items set ", clause: .set, keywordCase: .lower, tables: ["items"]),
        Case(text: "delete from items where ", clause: .where, keywordCase: .lower, tables: ["items"]),
        // Subqueries return to the outer clause, and the table inside is still named.
        Case(
            text: "select * from (select id from inner_t) x where ", clause: .where, keywordCase: .lower,
            tables: ["inner_t"], aliases: ["x"]),
        Case(
            text: "select * from t where id in (select id from u where ", clause: .where,
            keywordCase: .lower, tables: ["t", "u"]),
        // A semicolon ends the prior statement: nothing carries over.
        Case(text: "select 1 from t; ", clause: nil),
        Case(
            text: "select 1 from t; select * from u ", clause: .from, keywordCase: .lower, tables: ["u"]),
        // Strings and comments hold the caret.
        Case(
            text: "select * from t where name = 'bo", clause: .where, keywordCase: .lower, tables: ["t"],
            inString: true),
        Case(
            text: "select * from t where name = 'it''s' and ", clause: .where, keywordCase: .lower,
            tables: ["t"]),
        Case(
            text: "select * from t -- the users", clause: .from, keywordCase: .lower, tables: ["t"],
            inComment: true),
        Case(
            text: "select * from t -- note\nwhere ", clause: .where, keywordCase: .lower, tables: ["t"]),
        Case(
            text: "select * from t /* open", clause: .from, keywordCase: .lower, tables: ["t"],
            inComment: true),
        Case(
            text: "select * from t /* done */ where ", clause: .where, keywordCase: .lower, tables: ["t"]),
        // A keyword inside a string is no keyword.
        Case(text: "select 'from x where' from t ", clause: .from, keywordCase: .lower, tables: ["t"]),
        // The statement carried over a line break.
        Case(
            text: "select *\nfrom users\n", clause: .from, keywordCase: .lower, tables: ["users"]),
    ]

    @Test(
        "reads the clause, case, names and string or comment state of each preceding text", arguments: cases)
    func reads(_ expected: Case) {
        let position = SQLPosition.at(expected.text)
        #expect(position.openClause == expected.clause)
        #expect(position.keywordCase == expected.keywordCase)
        #expect(position.tables == expected.tables)
        #expect(position.aliases == expected.aliases)
        #expect(position.inString == expected.inString)
        #expect(position.inComment == expected.inComment)
        #expect(!position.isCut)
    }

    @Test("a field that will not say is unknown")
    func missingText() {
        #expect(SQLPosition.at(nil) == .unknown)
        #expect(SQLPosition.unknown.openClause == nil)
        #expect(SQLPosition.unknown.tables.isEmpty)
    }

    @Test("a window that may have cut the statement binds nothing")
    func cutWindow() {
        let tail = " and name = 'x' and age > 3 and city = 'y' and zip = 1 and "
        let long = "ere id = 4" + String(repeating: tail, count: 6)
        #expect(long.utf16.count >= InsertionPoint.precedingLimit)
        let cut = SQLPosition.at(long)
        #expect(cut == .unknown)
        #expect(cut.isCut)
        #expect(!cut.isMidStatement)
    }

    @Test("a full window holding a statement end reads the statement after it")
    func fullWindowAfterTerminator() {
        let filler = String(repeating: "select 1 from t; ", count: 20)
        let position = SQLPosition.at(filler + "select * from users where ")
        #expect(position.openClause == .where)
        #expect(position.tables == ["users"])
        #expect(!position.isCut)
    }

    @Test("a statement is mid-statement only where a clause is open outside a string and comment")
    func midStatement() {
        #expect(SQLPosition.at("select * from users ").isMidStatement)
        #expect(!SQLPosition.at("select * from users; ").isMidStatement)
        #expect(!SQLPosition.at("select * from users -- ").isMidStatement)
        #expect(!SQLPosition.at("select 'a").isMidStatement)
        #expect(!SQLPosition.at("what is a table ").isMidStatement)
    }
}
