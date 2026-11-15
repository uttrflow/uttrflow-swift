import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("The pass after the model keeps the marks code, a terminal and SQL were written with", .bug(id: 8275))
struct AfterModelWrittenMarksTests {
    @Test(
        "a colon, semicolon or comma written into the text stays",
        arguments: [
            ("color: red;", "styles.css", Destination.codeEditor),
            ("if count == 0:", "main.py", .codeEditor),
            ("cd src, ls", "", .terminal),
            ("VALUES (7, poetry)", "orders.sql", .sqlEditor),
        ])
    func marksStay(text: String, file: String, destination: Destination) {
        let app = AppContext(documentName: file.isEmpty ? nil : file, precedingText: "")
        let situation = Situation(app: app, insertion: app.insertionPoint, destination: destination)
        let pipeline = CleaningPipeline.afterModelPiece(
            digits: .none, situation: situation, heard: text, spoken: text)
        #expect(pipeline.run(Draft(text: text)).text == text)
    }
}
