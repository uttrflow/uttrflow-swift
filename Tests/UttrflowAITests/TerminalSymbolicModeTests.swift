import Testing
import UttrflowCore

@testable import UttrflowAI

/// Issue #8015: a symbolic permission mode said after chmod is written as one word.
@Suite("A terminal writes a spoken symbolic mode after chmod", .bug(id: 8015))
struct TerminalSymbolicModeTests {
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
        "plus or minus between the people and the permissions is the sign joined to both",
        arguments: [
            ("chmod plus x deploy dot sh", "chmod +x deploy.sh"),
            ("chmod u plus x run dot sh", "chmod u+x run.sh"),
            ("chmod g minus w notes dot txt", "chmod g-w notes.txt"),
            ("chmod ugo plus rwx data dot bin", "chmod ugo+rwx data.bin"),
            ("sudo chmod a minus x run dot sh", "sudo chmod a-x run.sh"),
            ("chmod u plus x, deploy", "chmod u+x, deploy"),
        ])
    func symbolicMode(spoken: String, expected: String) {
        #expect(Self.cleaned(spoken, into: Self.terminal) == expected)
    }

    @Test(
        "plus and minus elsewhere, or after a word the speaker marked, are not a mode",
        arguments: [
            ("chmod seven five five file", "chmod 755 file"),
            ("echo hello plus x", "echo hello plus x"),
            ("chmod u, plus x file", "chmod u plus x file"),
            ("chmod, u plus x file", "chmod u plus x file"),
            ("chmod. u plus x file", "chmod u plus x file"),
            ("chmod: plus x file", "chmod plus x file"),
            ("sudo, chmod u plus x file", "sudo chmod u plus x file"),
        ])
    func notAMode(spoken: String, expected: String) {
        #expect(Self.cleaned(spoken, into: Self.terminal) == expected)
    }

    @Test("prose after the word chmod keeps plus")
    func proseKeepsPlus() {
        let result = Self.cleaned("chmod plus x makes a file executable", into: Self.notes)
        #expect(result == "Chmod plus x makes a file executable.", "\(result)")
    }
}
