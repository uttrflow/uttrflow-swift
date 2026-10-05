import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("DigitGroupingPass")
struct DigitGroupingPassTests {
    @Test("regroups a numeral the model ungrouped after the rules grouped it")
    func regroupsModelNumeral() {
        let spoken = "marketing spend for march is 12,000"
        let pipeline = CleaningPipeline.afterModel(
            for: .standard(for: .spreadsheet), situation: .unknown, spoken: spoken)
        let finished = pipeline.run(Draft(keepingLineBreaks: "marketing spend for March is 12000"))
        #expect(finished.text == "marketing spend for March is 12,000")
    }

    @Test("keeps a trailing mark and leaves numerals the model was not handed grouped")
    func leavesUngroupedNumerals() {
        let pass = DigitGroupingPass(digits: .thousands, spokenText: "in 2024 we spent 12,000")
        let answer = Draft(keepingLineBreaks: "In 2024 we spent 12000.")
        #expect(pass.apply(answer).text == "In 2024 we spent 12,000.")
    }

    @Test("adds no grouping where the destination wants bare digits")
    func noGroupingForParsedDestinations() {
        let pass = DigitGroupingPass(digits: .none, spokenText: "limit 12,000")
        #expect(pass.apply(Draft(keepingLineBreaks: "LIMIT 12000")).text == "LIMIT 12000")
        let sql = CleaningPipeline.afterModel(
            for: .standard(for: .sqlEditor), situation: .unknown, spoken: "limit 12,000")
        #expect(sql.run(Draft(keepingLineBreaks: "LIMIT 12000")).text.contains("12000"))
    }
}
