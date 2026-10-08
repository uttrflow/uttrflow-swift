import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("Spreadsheet cell values")
struct SpreadsheetCellValueTests {
    private func cell(_ spoken: String, _ grouping: DigitGrouping) -> String {
        let situation = Situation(
            app: .unknown, insertion: .unknown, destination: .spreadsheet,
            numberStyle: NumberStyle(grouping: grouping))
        let pipeline = CleaningPipeline.beforeModel(for: .standard(for: .spreadsheet), situation: situation)
        return pipeline.run(Draft(text: spoken)).text
    }

    @Test(
        "writes each value shape the same way under either grouping",
        arguments: [
            ("twelve thousand", "12,000"), ("five percent", "5%"), ("twelve point five", "12.5"),
            ("twelve dollars fifty", "12 dollars 50"), ("minus forty two", "-42"),
            ("three point one four", "3.14"), ("twenty five thousand rupees", "25,000 rupees"),
            ("zero point five percent", "0.5%"),
        ])
    func sameUnderBothGroupings(spoken: String, written: String) {
        #expect(cell(spoken, .thousands) == written)
        #expect(cell(spoken, .indian) == written)
    }

    @Test("groups a lakh-sized value by the person's grouping")
    func groupingFollowsThePerson() {
        #expect(cell("one hundred fifty thousand", .thousands) == "150,000")
        #expect(cell("one hundred fifty thousand", .indian) == "1,50,000")
    }

    @Test("writes twelve fifty as a clock time, which a cell parses as a time")
    func twelveFiftyIsATime() {
        #expect(cell("twelve fifty", .thousands) == "12:50")
        #expect(cell("twelve fifty", .indian) == "12:50")
    }
}
