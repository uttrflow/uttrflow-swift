import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("Speech that describes a statement is not written as one", .bug(id: 4201))
struct SQLDescriptiveSpeechTests {
    private static func written(_ spoken: String) -> String {
        let app = AppContext(documentName: "report.sql", precedingText: "")
        let situation = Situation(app: app, insertion: app.insertionPoint, destination: .sqlEditor)
        let pipeline = CleaningPipeline.beforeModel(for: .standard(for: .sqlEditor), situation: situation)
        return pipeline.run(Draft(text: spoken)).text
    }

    @Test(
        "a description, a hedge or a clause name that is not a keyword stays as spoken",
        arguments: [
            "select everything from this table and join it to that table if there is this column join on it filter by date",
            "the select statement is slow",
            "filter by date",
        ])
    func descriptionStaysProse(spoken: String) {
        #expect(Self.written(spoken) == spoken)
    }

    @Test("a count of star is written as a call only before the table it counts")
    func countOfStarNeedsASourceTable() {
        #expect(Self.written("select count of star from orders").contains("COUNT(*)"))
        #expect(!Self.written("select count of star").contains("COUNT(*)"))
    }
}
