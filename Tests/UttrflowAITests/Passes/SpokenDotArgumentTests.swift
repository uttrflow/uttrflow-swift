import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("A spoken dot at a command line", .bug(id: 7878))
struct SpokenDotArgumentTests {
    private let prose = SpokenPunctuationPass()
    private let terminal = SpokenPunctuationPass(destination: .terminal)

    @Test(
        "joins the names a dot stands between, and writes a dot that ends the command",
        arguments: [
            ("python3 dash m http dot server", "python3 -m http.server"),
            ("python3 dash m pip dot main", "python3 -m pip.main"),
            ("git add dot", "git add ."),
            ("cd dot dot", "cd .."),
            ("ls dash la dot", "ls -la ."),
        ]
    )
    func writesDots(input: String, expected: String) {
        #expect(cleaned(input, by: terminal) == expected)
    }

    @Test(
        "writes the reported dictations through every pass",
        arguments: [
            ("python3 dash m http dot server", "python3 -m http.server"),
            ("git add dot", "git add ."),
            ("cd dot dot", "cd .."),
            ("Docker build dash dash no dash cache dot.", "docker build --no-cache ."),
        ]
    )
    func writesReportedDictations(spoken: String, expected: String) {
        let app = AppContext(applicationName: "Terminal", bundleIdentifier: "com.apple.Terminal")
        let situation = SituationResolver.resolve(from: app)
        let formatter = DestinationFormatter.standard(for: situation.destination)
        let pipeline = CleaningPipeline.standard(for: formatter, situation: situation)
        #expect(pipeline.run(Draft(text: spoken)).text == expected)
    }

    @Test(
        "leaves a dot in prose and beside a number or a determiner as a word",
        arguments: [
            "echo the dot product", "python three dot twelve", "add a dot", "put the dot", "echo dot product",
            "she tapped dot dash dot on the wall",
        ]
    )
    func leavesProse(input: String) {
        #expect(cleaned(input, by: terminal) == input)
    }

    @Test("keeps the same words outside a command line")
    func leavesOtherDestinations() {
        #expect(cleaned("git add dot", by: prose) == "git add dot")
        #expect(cleaned("run http dot server", by: prose) == "run http dot server")
    }
}
