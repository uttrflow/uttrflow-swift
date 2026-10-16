import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("A spoken name and the number after its colon", .bug(id: 7880))
struct SpokenTagTests {
    private let prose = SpokenPunctuationPass()
    private let terminal = SpokenPunctuationPass(destination: .terminal)

    @Test(
        "writes an image tag and a port pair as one word at a command line",
        arguments: [
            ("postgres colon sixteen", "postgres:16"),
            ("docker pull node colon twenty", "docker pull node:20"),
            ("run postgres colon sixteen now", "run postgres:16 now"),
            ("publish eight thousand colon eight thousand", "publish 8000:8000"),
            ("docker run dash p eight zero eight zero colon eighty", "docker run -p 8080:80"),
        ]
    )
    func writesTaggedNames(input: String, expected: String) {
        #expect(cleaned(input, by: terminal) == expected)
    }

    @Test("writes the reported dictation through every pass")
    func writesReportedDictation() {
        let app = AppContext(applicationName: "Terminal", bundleIdentifier: "com.apple.Terminal")
        let situation = SituationResolver.resolve(from: app)
        let formatter = DestinationFormatter.standard(for: situation.destination)
        let pipeline = CleaningPipeline.standard(for: formatter, situation: situation)
        #expect(pipeline.run(Draft(text: "postgres colon sixteen")).text == "postgres:16")
    }

    @Test("keeps a colon before a word as a mark, and a colon outside a command line")
    func leavesOtherColons() {
        #expect(cleaned("git commit dash m fix colon add tests", by: terminal) == "git commit -m fix colon add tests")
        #expect(cleaned("postgres colon sixteen", by: prose) == "postgres: sixteen")
    }
}
