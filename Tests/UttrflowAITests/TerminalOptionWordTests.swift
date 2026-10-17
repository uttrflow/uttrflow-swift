import Testing
import UttrflowCore

@testable import UttrflowAI

/// Issue #8014: a short option said as one word of three or more letters is written whole at a shell prompt.
@Suite("A terminal writes a dash and one option word as the option", .bug(id: 8014))
struct TerminalOptionWordTests {
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
        "an option said as a single word of any length keeps its dash",
        arguments: [
            ("tar dash xzf archive dot tar dot gz", "tar -xzf archive.tar.gz"),
            ("sudo tar dash xzf archive dot tar dot gz", "sudo tar -xzf archive.tar.gz"),
            ("sudo java dash version", "sudo java -version"),
            ("java dash version", "java -version"),
            ("ls dash lah", "ls -lah"),
            ("xcodebuild dash scheme app", "xcodebuild -scheme app"),
        ])
    func optionWord(spoken: String, expected: String) {
        #expect(Self.cleaned(spoken, into: Self.terminal) == expected)
    }

    @Test(
        "a number, a function word or a long option marker after dash is not an option word",
        arguments: [
            ("kill dash nine one two three four", "kill -9 1234"),
            ("head dash twenty notes dot txt", "head -20 notes.txt"),
            ("git push dash dash force", "git push --force"),
            ("ls dash l a", "ls -la"),
            ("cd tilde slash my dash project", "cd ~/my-project"),
            ("git checkout dash b fix dash login", "git checkout -b fix-login"),
            ("rm dash rf build dash output", "rm -rf build-output"),
        ])
    func notAnOptionWord(spoken: String, expected: String) {
        #expect(Self.cleaned(spoken, into: Self.terminal) == expected)
    }

    @Test("a dash after a word that is no program is never an option")
    func notAfterAnArgument() {
        let result = Self.cleaned("alpha dash beta", into: Self.terminal)
        #expect(!result.contains("alpha -beta"), "\(result)")
    }

    @Test("prose keeps the word dash before an ordinary word")
    func proseKeepsDash() {
        let result = Self.cleaned("the flag is dash version", into: Self.notes)
        #expect(result.contains("dash"), "\(result)")
    }
}
