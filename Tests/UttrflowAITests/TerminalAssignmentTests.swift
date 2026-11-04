import Testing
import UttrflowCore

@testable import UttrflowAI

/// Issue #7943: a spoken "equals" between a name and its value at a shell prompt is written as "=".
@Suite("A terminal writes a spoken equals between a name and a value as an assignment", .bug(id: 7943))
struct TerminalAssignmentTests {
    private static let terminal = AppContext(
        applicationName: "Terminal", bundleIdentifier: "com.apple.Terminal")
    private static let notes = AppContext(applicationName: "Notes", bundleIdentifier: "com.apple.Notes")

    private static func cleaned(_ spoken: String, into app: AppContext) -> String {
        let situation = SituationResolver.resolve(from: app)
        let formatter = DestinationFormatter.standard(for: situation.destination)
        return CleaningPipeline.standard(for: formatter, situation: situation)
            .run(Draft(text: spoken)).text
    }

    @Test(
        "an environment variable and a long option take their value with an equals sign",
        arguments: [
            ("export NODE underscore ENV equals production", "export NODE_ENV=production"),
            ("git log dash dash since equals yesterday", "git log --since=yesterday"),
            ("docker run dash dash name equals web nginx", "docker run --name=web nginx"),
            ("FOO equals bar make", "FOO=bar make"),
        ])
    func assignment(spoken: String, expected: String) {
        #expect(Self.cleaned(spoken, into: Self.terminal) == expected)
    }

    @Test("prose outside a command line keeps the word")
    func proseKeepsTheWord() {
        #expect(Self.cleaned("the total equals the sum", into: Self.notes) == "The total equals the sum.")
    }
}
