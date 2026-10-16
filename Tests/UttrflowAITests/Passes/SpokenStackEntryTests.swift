import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("A spoken directory-stack entry", .bug(id: 7876))
struct SpokenStackEntryTests {
    private let prose = SpokenPunctuationPass()
    private let terminal = SpokenPunctuationPass(destination: .terminal)

    @Test(
        "writes the home mark and the number after it as one word at a command line",
        arguments: [
            ("head tilde one", "head ~1"),
            ("cd tilde two", "cd ~2"),
            ("pushd tilde twelve", "pushd ~12"),
        ]
    )
    func writesStackEntries(input: String, expected: String) {
        #expect(cleaned(input, by: terminal) == expected)
    }

    @Test("writes the reported dictation through every pass")
    func writesReportedDictation() {
        let app = AppContext(applicationName: "Terminal", bundleIdentifier: "com.apple.Terminal")
        let situation = SituationResolver.resolve(from: app)
        let formatter = DestinationFormatter.standard(for: situation.destination)
        let pipeline = CleaningPipeline.standard(for: formatter, situation: situation)
        #expect(pipeline.run(Draft(text: "head tilde one")).text == "head ~1")
    }

    @Test("keeps the words in prose and keeps a name after the home mark apart")
    func leavesProse() {
        #expect(cleaned("a tilde one over the n", by: prose) == "a tilde one over the n")
        #expect(cleaned("the tilde key is broken", by: terminal) == "the tilde key is broken")
    }
}
