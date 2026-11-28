import Testing

@testable import UttrflowCore
@testable import UttrflowPipeline

@Suite("A date said in a query editor")
struct SQLDateLiteralScenarioTests {
    @Test("is written as one quoted literal after a comparison word")
    func quotedLiteral() async {
        let said = GoldenScenarios.said(
            GoldenScenarios.sql(before: "SELECT * FROM orders\n"), "where created after January 1 2026")
        let written = await ScenarioDriver.run(said).writes.joined()
        #expect(written.contains("'2026-01-01'"), "wrote \(written)")
    }

    @Test("stays prose in a document")
    func proseKeepsItsDate() async {
        let said = GoldenScenarios.said(GoldenScenarios.prose("Notes\n"), "we met after January 1 2026")
        let written = await ScenarioDriver.run(said).writes.joined()
        #expect(!written.contains("'2026-01-01'"), "wrote \(written)")
    }
}
