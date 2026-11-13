import Testing

@testable import UttrflowCore

@Suite("SQL quoting evidence")
struct SQLQuotingEvidenceTests {
    @Test("the style is read from names, not from strings, comments' text or arrays")
    func readsNamesOnly() {
        #expect(SQLQuoting.identifierStyle(in: "select `a` from t") == .backtick)
        #expect(SQLQuoting.identifierStyle(in: "select [a b] from t") == .bracket)
        #expect(SQLQuoting.identifierStyle(in: "select \"a\" from t") == .double)
        #expect(SQLQuoting.identifierStyle(in: "where x = 'say \"hi\" `now`'") == nil)
        #expect(SQLQuoting.identifierStyle(in: "select [1, 2] from t") == nil)
        #expect(SQLQuoting.identifierStyle(in: nil) == nil)
    }

    @Test("a value doubles each apostrophe")
    func valueDoubles() {
        #expect(SQLQuoting.value("o'brien") == "'o''brien'")
        #expect(SQLQuoting.lastWord(of: "where a = ") == "=")
    }
}
