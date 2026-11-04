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
        let commit = "git commit dash m fix colon add tests"
        #expect(cleaned(commit, by: terminal) == "git commit -m fix colon add tests")
        #expect(cleaned("postgres colon sixteen", by: prose) == "postgres: sixteen")
    }

    @Test(
        "writes a port pair as one word after a port word or an option, outside a command line",
        .bug(id: 7902),
        arguments: [
            ("forward port three thousand colon three thousand", "forward port 3000:3000"),
            ("map ports eight zero eight zero colon eighty", "map ports 8080:80"),
            ("run it with -p eight zero eight zero colon eighty", "run it with -p 8080:80"),
        ]
    )
    func writesPortPairsInProse(input: String, expected: String) {
        #expect(cleaned(input, by: prose) == expected)
        #expect(cleaned(input, by: SpokenPunctuationPass(destination: .codeEditor)) == expected)
    }

    @Test(
        "writes a port pair whole through the shipped pipeline in plain text and a code editor",
        .bug(id: 7902),
        arguments: [
            ("TextEdit", "com.apple.TextEdit", "forward port three thousand colon three thousand"),
            (
                "Visual Studio Code", "com.microsoft.VSCode",
                "forward port three thousand colon three thousand"
            ),
            (
                "Visual Studio Code", "com.microsoft.VSCode",
                "docker run dash dash rm dash p eight zero eight zero colon eighty nginx"
            ),
        ]
    )
    func writesPortPairThroughPipeline(name: String, bundle: String, input: String) {
        let app = AppContext(applicationName: name, bundleIdentifier: bundle)
        let situation = SituationResolver.resolve(from: app)
        let formatter = DestinationFormatter.standard(for: situation.destination)
        let pipeline = CleaningPipeline.standard(for: formatter, situation: situation)
        let text = pipeline.run(Draft(text: input)).text
        #expect(text.contains(/\d:\d/) && !text.contains(": "), "\(text)")
    }

    @Test(
        "keeps a colon between numbers as a mark where no port word or option stands before them",
        .bug(id: 7902),
        arguments: [
            "the score was two colon one", "the port held. two colon one",
            "the port is open and two colon one",
        ]
    )
    func leavesUncuedNumberColons(input: String) {
        #expect(cleaned(input, by: prose).firstMatch(of: /\d:\d/) == nil)
    }
}
