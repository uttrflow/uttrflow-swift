import Testing
import UttrflowCore

@testable import UttrflowAI

/// Issue #3554: a numeric correction takes back the whole spoken number, never part of it.
@Suite("A numeric correction takes back the whole spoken number", .bug(id: 3554))
struct NumericCorrectionWholeNumberTests {
    private let pipeline = CleaningPipeline.standard(
        for: DestinationFormatter.standard(for: .plain), situation: .unknown)

    @Test(
        "a numeric correction replaces the whole discarded number",
        arguments: [
            ("please book room two oh one no sorry two oh three", "Please book room 203."),
            ("room two oh one no sorry three oh four", "Room 304."),
            ("call me at five sorry six", "Call me at 6."),
            ("the code is one two three no sorry one two four", "The code is 124."),
        ]
    )
    func replacesWholeNumber(spoken: String, written: String) {
        #expect(pipeline.run(Draft(text: spoken)).text == written)
    }

    @Test(
        "a numeric correction writes what the restart alone would",
        arguments: [
            ("set the alarm for six no seven thirty", "set the alarm for seven thirty"),
            ("please book room two oh one no sorry two oh three", "please book room two oh three"),
            ("oh one no sorry two", "oh two"),
        ]
    )
    func matchesTheRestart(spoken: String, restart: String) {
        #expect(pipeline.run(Draft(text: spoken)).text == pipeline.run(Draft(text: restart)).text)
    }
}
