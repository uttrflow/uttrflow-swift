import Testing

@testable import UttrflowAI

@Suite("SQL date literals")
struct SQLDateLiteralPassTests {
    @Test(
        "a complete date after a comparison word becomes one quoted literal",
        arguments: [
            ("created after January 1, 2026", "created after '2026-01-01'"),
            ("created before the 1st of March 2026", "created before '2026-03-01'"),
            ("created on 2026/01/09", "created on '2026-01-09'"),
            ("created since 2026-12-31", "created since '2026-12-31'"),
        ])
    func rewrites(spoken: String, written: String) {
        #expect(SQLDateLiteralPass.literals(in: spoken) == written)
    }

    @Test(
        "a partial, impossible or unmarked date stays as written",
        arguments: [
            "created after January 2026",
            "created after February 30, 2026",
            "created in January 1, 2026",
            "created after last week",
        ])
    func leavesAlone(spoken: String) {
        #expect(SQLDateLiteralPass.literals(in: spoken) == spoken)
    }

    @Test("it is idempotent")
    func idempotent() {
        let once = SQLDateLiteralPass.literals(in: "created after January 1, 2026")
        #expect(SQLDateLiteralPass.literals(in: once) == once)
    }
}
