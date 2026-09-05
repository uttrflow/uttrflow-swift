import Testing

@testable import UttrflowAI

@Suite("TextTidy")
struct TextTidyTests {
    @Test(
        "collapses every run of whitespace and trims the ends",
        arguments: [
            ("  hello   there  ", "hello there"),
            ("hello\tthere", "hello there"),
            ("hello\n\nthere", "hello there"),
            ("hello", "hello"),
            ("   ", ""),
            ("", ""),
        ]
    )
    func collapseWhitespace(input: String, expected: String) {
        #expect(TextTidy.collapseWhitespace(input) == expected)
    }

    /// A model's line breaks can be the whole point: dictated code comes back as several lines.
    @Test(
        "keeps the line breaks a model meant, while still tidying the spacing",
        arguments: [
            ("def add(a, b):\n    return a + b", "def add(a, b):\nreturn a + b"),
            ("hello   there", "hello there"),
            ("hello\n\nthere", "hello\n\nthere"),
            ("  hello \n there  ", "hello\nthere"),
            ("hello", "hello"),
            ("   ", ""),
            ("", ""),
        ]
    )
    func collapseSpacing(input: String, expected: String) {
        #expect(TextTidy.collapseSpacing(input) == expected)
    }

    @Test("dictated code keeps its shape and gains no stray full stop")
    func dictatedCodeSurvivesTheGenerativePath() {
        let modelAnswer = "def add(a, b):\n    return a + b"
        let finished = TextTidy.ensureTerminalPunctuation(TextTidy.collapseSpacing(modelAnswer))
        #expect(finished.contains("\n"), "the line break was flattened away")
        #expect(!finished.hasSuffix("."), "a full stop was added to code")
    }

    @Test(
        "finishes a sentence that has no ending",
        arguments: [("hello there", "hello there."), ("42", "42.")]
    )
    func addsTerminalPunctuation(input: String, expected: String) {
        #expect(TextTidy.ensureTerminalPunctuation(input) == expected)
    }

    @Test(
        "leaves text that already ends properly",
        arguments: ["hello.", "hello!", "hello?", "hello…", "hello,", "\"hello\""]
    )
    func keepsExistingPunctuation(input: String) {
        #expect(TextTidy.ensureTerminalPunctuation(input) == input)
    }

    @Test(
        "does not finish something that looks like code",
        arguments: [
            "get_user(id)",
            "SELECT * FROM user;",
            "let x = [1, 2, 3]",
            "func main() {}",
            "line one\nline two",
        ]
    )
    func leavesCodeAlone(input: String) {
        #expect(TextTidy.ensureTerminalPunctuation(input) == input)
    }

    @Test("does nothing to empty text")
    func emptyText() {
        #expect(TextTidy.ensureTerminalPunctuation("") == "")
    }
}
