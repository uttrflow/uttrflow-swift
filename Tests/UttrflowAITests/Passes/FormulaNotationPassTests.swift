import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("A spoken formula in a spreadsheet cell is written as the formula")
struct FormulaNotationPassTests {
    private func written(
        _ spoken: String, after precedingText: String = "", mode: AdapterMode = .auto
    ) -> String {
        let app = AppContext(precedingText: precedingText)
        let situation = Situation(
            app: app, insertion: app.insertionPoint, destination: .spreadsheet, adapterMode: mode)
        let formatter = DestinationFormatter.standard(for: .spreadsheet)
        return CleaningPipeline.standard(for: formatter, situation: situation)
            .run(Draft(text: spoken)).text
    }

    @Test(
        "writes references, ranges, functions, operators and strings in an empty cell",
        arguments: [
            ("equals sum open paren a one to a ten close paren", "=SUM(A1:A10)"),
            ("equals sum open paren b two through b nine close paren", "=SUM(B2:B9)"),
            ("formula average open paren c three to c twelve close paren", "=AVERAGE(C3:C12)"),
            ("equals a one plus b one", "=A1+B1"),
            ("equals a one times b one", "=A1*B1"),
            ("equals a one divided by b one", "=A1/B1"),
            ("equals a one minus a two", "=A1-A2"),
            ("equals dollar a dollar one", "=$A$1"),
            (
                "equals sum open paren dollar a dollar one to dollar a dollar ten close paren",
                "=SUM($A$1:$A$10)"
            ),
            (
                "equals if open paren a one greater than ten comma quote yes quote comma quote no quote close paren",
                "=IF(A1>10,\"yes\",\"no\")"
            ),
            (
                "equals if open paren a one greater than or equal to ten comma one comma zero close paren",
                "=IF(A1>=10,1,0)"
            ),
            ("equals a one not equals b one", "=A1<>B1"),
            ("equals a one less than b one", "=A1<B1"),
            ("equals a one equals b one", "=A1=B1"),
            (
                "equals vlookup open paren a two comma quote my data quote bang a one to b ten comma two comma false close paren",
                "=VLOOKUP(A2,'my data'!A1:B10,2,FALSE)"
            ),
            ("equals round open paren a one comma two close paren", "=ROUND(A1,2)"),
            ("equals today open paren close paren", "=TODAY()"),
            ("equals a twenty five plus b one hundred", "=A25+B100"),
        ])
    func writesFormula(spoken: String, expected: String) {
        #expect(written(spoken) == expected)
    }

    @Test("continues a formula already in the cell without an opening word")
    func continuesFormula() {
        #expect(written("a one to a ten close paren", after: "=SUM(") == "A1:A10)")
        #expect(written("plus b one", after: "=A1") == "+B1")
    }

    @Test("separates arguments with the system locale's separator")
    func usesSeparator() {
        let pass = FormulaNotationPass(cellIsEmpty: true, argumentSeparator: ";")
        let draft = pass.apply(Draft(text: "equals max open paren a one comma a two close paren"))
        #expect(draft.text == "=MAX(A1;A2)")
    }

    @Test(
        "leaves a cell that is not a formula as it was",
        arguments: [
            "a one bedroom flat", "b two b flat", "sum of the costs", "plus or minus ten",
            "we need a ten minute break", "open the window", "quote of the day",
            "it equals the total", "the formula is simple", "a one to a ten", "schedule a two",
        ])
    func abstainsInPlainCell(spoken: String) {
        #expect(written(spoken) == written(spoken, mode: .prose))
    }

    @Test(
        "does not open a formula in a cell that already holds text",
        arguments: [
            ("equals sum open paren a one close paren", "Budget "),
            ("equals a one", "hello"),
            ("formula a one to a ten", "note: "),
        ])
    func abstainsInFilledCell(spoken: String, preceding: String) {
        #expect(written(spoken, after: preceding) == written(spoken, after: preceding, mode: .prose))
    }

    @Test("writes plain prose when the field is set to prose")
    func proseMode() {
        #expect(written("equals a one plus b one", mode: .prose) != "=A1+B1")
    }
}
