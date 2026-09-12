import Testing

@testable import UttrflowAI

/// Every deterministic repair in `TextTidy`.
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

    @Test("text is read as lower-cased runs of letters and digits")
    func words() {
        #expect(TextTidy.words("PaymentSheet.swift") == ["paymentsheet", "swift"])
        #expect(TextTidy.words("set-user-prefs!") == ["set", "user", "prefs"])
        #expect(TextTidy.words("—:—").isEmpty)
    }

    /// A recogniser's line breaks are chunking artefacts; a model's are meant, as with dictated code.
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

    /// Dictating code is a use this product serves, and its line breaks are the shape of it.
    @Test("dictated code keeps its shape through the generative path")
    func dictatedCodeSurvivesTheGenerativePath() {
        let modelAnswer = "def add(a, b):\n    return a + b"
        #expect(TextTidy.collapseSpacing(modelAnswer).contains("\n"), "the line break was flattened away")
    }

    @Test("does nothing to empty text")
    func emptyText() {
        #expect(TextTidy.collapseSpacing("") == "")
        #expect(TextTidy.collapseWhitespace("") == "")
    }
}
