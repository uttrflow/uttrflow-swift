import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("A commit message is written as a commit message")
struct CommitMessageTests {
    private func written(_ spoken: String, in app: AppContext) -> String {
        let situation = SituationResolver.resolve(from: app)
        let formatter = DestinationFormatter.standard(for: situation)
        return CleaningPipeline.standard(for: formatter, situation: situation).run(Draft(text: spoken)).text
    }

    private func editor(after preceding: String = "") -> AppContext {
        AppContext(
            applicationName: "Code", bundleIdentifier: "com.microsoft.VSCode", documentName: "COMMIT_EDITMSG",
            precedingText: preceding, accessibilityRole: "AXTextArea", isMultiline: true)
    }

    private func terminal(after preceding: String) -> AppContext {
        AppContext(
            applicationName: "Terminal", bundleIdentifier: "com.apple.Terminal", precedingText: preceding)
    }

    @Test(
        "writes a subject with no full stop, and a body after a blank line only where one was said",
        arguments: [
            ("fix the login bug when the token expires", "Fix the login bug when the token expires"),
            ("update readme", "Update README"),
            ("bump version to two point three point one", "Bump version to 2.3.1"),
            ("fix the login bug. the token expired", "Fix the login bug. The token expired"),
            (
                "add retry to the upload client new paragraph the client now retries three times",
                "Add retry to the upload client\n\nThe client now retries 3 times"
            ),
            (
                "remove the dead code path new line and the unused flag",
                "Remove the dead code path\nAnd the unused flag"
            ),
        ])
    func writesSubject(spoken: String, expected: String) {
        #expect(written(spoken, in: editor()) == expected)
    }

    @Test("keeps a long subject whole")
    func longSubject() {
        let spoken =
            "this is a very long subject line that keeps going well past the usual limit of seventy two characters because the speaker did not stop talking"
        let out = written(spoken, in: editor())
        #expect(out.count > 100)
        #expect(out.hasSuffix("did not stop talking"))
        #expect(!out.contains("\n"))
    }

    @Test(
        "adds no second blank line where the caret already follows one",
        arguments: [
            ("new paragraph signed off by someone", "Add retry\n\n", "Signed off by someone"),
            ("new paragraph signed off by someone", "Add retry\n", "\nSigned off by someone"),
            (
                "the client now retries three times with backoff.", "Add retry\n\n",
                "The client now retries 3 times with backoff"
            ),
        ])
    func bodyAfterBlankLine(spoken: String, preceding: String, expected: String) {
        #expect(written(spoken, in: editor(after: preceding)) == expected)
    }

    @Test(
        "writes the words of a message typed after git commit dash m as said, with no line break",
        arguments: [
            ("fix the login bug when the token expires", "fix the login bug when the token expires"),
            ("fix the login bug new paragraph explain why", "fix the login bug explain why"),
            ("update readme", "update README"),
        ])
    func insideTheQuotedArgument(spoken: String, expected: String) {
        let out = written(spoken, in: terminal(after: "$ git commit -m \""))
        #expect(out == expected)
        #expect(!out.contains("\n"))
    }

    @Test(
        "writes a whole commit command with balanced quotes",
        arguments: [
            ("git commit dash m quote fix the login bug quote", "git commit -m \"fix the login bug\""),
            ("git commit dash am quote fix typo quote", "git commit -am \"fix typo\""),
        ])
    func wholeCommand(spoken: String, expected: String) {
        #expect(written(spoken, in: terminal(after: "$ ")) == expected)
    }

    @Test(
        "leaves a sentence about committing as a sentence in a notes document",
        arguments: [
            "we should commit the changes tomorrow", "please write a better commit message next time",
            "the commit subject is too long", "he forgot to commit before leaving",
        ])
    func proseAboutCommits(spoken: String) {
        let notes = AppContext(
            applicationName: "Notes", bundleIdentifier: "com.apple.Notes", precedingText: "")
        let out = written(spoken, in: notes)
        #expect(out.hasSuffix("."))
        #expect(!out.contains("\"") && !out.contains("git") && !out.contains("-m"))
    }
}
