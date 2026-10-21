import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("A hyphenated name that begins with a possessive at a command line", .bug(id: 7942))
struct SpokenArgumentNameTests {
    private static func terminal(_ spoken: String) -> String {
        let app = AppContext(applicationName: "Terminal", bundleIdentifier: "com.apple.Terminal")
        let situation = SituationResolver.resolve(from: app)
        let formatter = DestinationFormatter.standard(for: situation.destination)
        let pipeline = CleaningPipeline.standard(for: formatter, situation: situation)
        return pipeline.run(Draft(text: spoken)).text
    }

    @Test(
        "joins the parts of an argument that begins with my",
        arguments: [
            ("docker run dash dash name my dash container nginx", "docker run --name my-container nginx"),
            ("git checkout dash b my dash feature", "git checkout -b my-feature"),
            ("mkdir my dash folder", "mkdir my-folder"),
            ("kubectl logs my dash app", "kubectl logs my-app"),
            ("cd my dash project", "cd my-project"),
            ("git clone my dash repo", "git clone my-repo"),
        ]
    )
    func joinsArguments(spoken: String, expected: String) {
        #expect(Self.terminal(spoken) == expected)
    }

    @Test("keeps the word where a function word follows the dash")
    func keepsProse() {
        #expect(Self.terminal("echo my dash of salt") != "echo my-of salt")
    }

    @Test("keeps the word outside a command line")
    func keepsWordOutsideATerminal() {
        let prose = SpokenPunctuationPass()
        #expect(cleaned("my dash container", by: prose) != "my-container")
    }
}
