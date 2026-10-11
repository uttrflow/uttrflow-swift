import Testing

@testable import UttrflowCore

/// The layout convention of the statement before the caret, read from invented preceding text.
@Suite("SQL layout reading")
struct SQLLayoutReadingTests {
    @Test("a missing, empty or single-clause field shows no convention")
    func noConvention() {
        for text in [nil, "", "select *", "-- note", "select 1;\n"] as [String?] {
            #expect(SQLLayout.at(text).convention == .unknown, "\(String(describing: text))")
        }
    }

    @Test("clauses sharing a line are one line, and a clause opening a later line is clause lines")
    func readsConvention() {
        #expect(SQLLayout.at("select * from users where id = 1").convention == .oneLine)
        #expect(SQLLayout.at("select *\nfrom users").convention == .clauseLines)
        #expect(SQLLayout.at("select a,\n  b from users").convention == .oneLine)
    }

    @Test("only the last statement and only top-level clauses count")
    func readsLastStatement() {
        #expect(SQLLayout.at("select *\nfrom users;\nselect * from orders").convention == .oneLine)
        #expect(SQLLayout.at("select * from (select 1\nfrom t) x").convention == .oneLine)
        #expect(SQLLayout.at("select * from users; -- from\n").convention == .oneLine)
        #expect(SQLLayout.at("select 'x\nfrom y' from users").convention == .oneLine)
    }

    @Test("indent comes from the lines that open the clauses, in the unit the script uses")
    func readsIndent() {
        let spaced = SQLLayout.at("select a\n  from t\n    join u on u.id = t.id\n  where x")
        #expect(spaced.clauseIndent == "  ")
        #expect(spaced.joinIndent == "    ")
        let tabbed = SQLLayout.at("select a\n\tfrom t\n\twhere x")
        #expect(tabbed.joinIndent == "\t\t")
        #expect(SQLLayout.at("select a\nfrom t").joinIndent == "  ")
        #expect(SQLLayout.at("select a\n    from t").joinIndent == "        ")
    }

    @Test("a join keeps the words of its name together and a delete's from is not a clause")
    func readsJoinsAndDeletes() {
        let joined = SQLLayout.at("select a\nfrom t\n  left outer join u on 1 = 1\n")
        #expect(joined.convention == .clauseLines)
        #expect(joined.joinIndent == "  ")
        #expect(SQLLayout.at("delete from t").convention == .unknown)
        #expect(SQLLayout.at("delete from t where x").convention == .oneLine)
        #expect(SQLLayout.at("group by a order by b").convention == .oneLine)
        #expect(SQLLayout.at("select a /* x\nfrom */ from t").convention == .oneLine)
    }

    @Test("the caret line and the open parentheses are reported")
    func readsCaret() {
        let layout = SQLLayout.at("select a\nfrom t where id")
        #expect(layout.caretLine == "from t where id")
        #expect(layout.isMidStatement)
        #expect(SQLLayout.at("select a\nfrom t where id in (").depth == 1)
        #expect(SQLLayout.at("select a\nfrom t\n").caretLine == "")
        #expect(SQLLayout.opening("group", next: "x", previous: nil) == nil)
        #expect(SQLLayout.opening("order", next: "by", previous: nil) == .clause)
        #expect(SQLLayout.opening("order by", next: nil, previous: nil) == .clause)
        #expect(SQLLayout.at(nil).indent(for: .clause).isEmpty)
    }
}
