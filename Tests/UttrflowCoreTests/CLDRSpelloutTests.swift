import Testing

@testable import UttrflowCore

@Suite("The CLDR spell-out extract against the hand number tables")
struct CLDRSpelloutTests {
    @Test("the extract loads from the bundle and holds cardinals and ordinals")
    func extractLoads() {
        #expect(CLDRSpellout.table.source == .bundled)
        #expect(CLDRSpellout.table.rows.contains { $0.id == "fortieth" && $0.value == 40 })
        #expect(CLDRSpellout.table.rows.contains { $0.id == "thirteen" && $0.value == 13 })
    }

    /// The two lists are the ones `Docs/number-word-coverage.md` decides; a change to either shows here.
    @Test("the hand tables miss exactly the words the coverage page lists")
    func coverageIsAsDocumented() {
        let coverage = CLDRSpellout.coverage
        let missing = [
            "billionth", "hundredth", "millionth", "quadrillion", "quadrillionth", "thousandth",
            "trillionth", "zeroth",
        ]
        #expect(coverage.missing == missing)
        #expect(coverage.handOnly == ["crore", "lac", "lakh"])
    }
}
