import Testing
import UttrflowCore

@testable import UttrflowAI

/// Issue #7944: a spoken glob at a shell prompt is the asterisk, so "rm star dot tmp" is "rm *.tmp".
@Suite("A terminal writes a spoken star as the glob character", .bug(id: 7944))
struct TerminalGlobStarTests {
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
        "star is the glob in a command line",
        arguments: [
            ("rm star dot tmp", "rm *.tmp"),
            ("ls star dot txt", "ls *.txt"),
            ("du dash sh star", "du -sh *"),
        ])
    func writesGlob(spoken: String, expected: String) {
        #expect(Self.cleaned(spoken, into: Self.terminal) == expected)
    }

    @Test("star stays a word outside a terminal")
    func wordElsewhere() {
        #expect(Self.cleaned("she is a star dot", into: Self.notes).contains("star"))
    }
}
