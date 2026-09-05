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

    /// The generative path in order, so the newline guard in `ensureTerminalPunctuation` stays reachable.
    @Test("dictated code keeps its shape and gains no stray full stop")
    func dictatedCodeSurvivesTheGenerativePath() {
        let modelAnswer = "def add(a, b):\n    return a + b"
        let finished = TextTidy.ensureTerminalPunctuation(TextTidy.collapseSpacing(modelAnswer))
        #expect(finished.contains("\n"), "the line break was flattened away")
        #expect(!finished.hasSuffix("."), "a full stop was added to code")
    }

    @Test(
        "removes the sounds people make while thinking",
        arguments: [
            ("um hello there", "hello there"),
            ("hello uh there", "hello there"),
            ("er hello", "hello"),
            ("hello there hmm", "hello there"),
            ("Um, hello", "hello"),
            ("uh um er hello", "hello"),
        ]
    )
    func removesFillers(input: String, expected: String) {
        #expect(TextTidy.removeFillers(input) == expected)
    }

    /// Ordinary words far more often than filler; removing them changes what the speaker said.
    @Test(
        "keeps words that only sometimes act as filler",
        arguments: [
            "I would like a coffee",
            "well done everyone",
            "so the answer is four",
            "you know the answer",
            "that is a hard problem",
        ]
    )
    func keepsAmbiguousWords(input: String) {
        #expect(TextTidy.removeFillers(input) == input)
    }

    @Test("removes the doubled word a false start leaves behind")
    func removesStammer() {
        #expect(TextTidy.removeFillers("the the deployment") == "the deployment")
        #expect(TextTidy.removeFillers("I I think so") == "I think so")
    }

    /// A repeated long word is emphasis or a real repetition, not a stammer.
    @Test("keeps a repeated long word")
    func keepsRepeatedLongWord() {
        #expect(TextTidy.removeFillers("really really good") == "really really good")
    }

    @Test(
        "capitalises the start of every sentence",
        arguments: [
            ("hello there", "Hello there"),
            ("hello. there", "Hello. There"),
            ("hello! there? okay", "Hello! There? Okay"),
            ("  hello", "  Hello"),
            ("42 things", "42 things"),
            ("", ""),
        ]
    )
    func capitalisesSentences(input: String, expected: String) {
        #expect(TextTidy.capitaliseSentences(input) == expected)
    }

    @Test(
        "capitalises the pronoun I where it stands alone",
        arguments: [
            ("i think so", "I think so"),
            ("well i think", "well I think"),
            ("i", "I"),
            ("i, therefore", "I, therefore"),
        ]
    )
    func capitalisesPronoun(input: String, expected: String) {
        #expect(TextTidy.capitalisePronounI(input) == expected)
    }

    @Test(
        "leaves an i that is part of another word alone",
        arguments: ["it is fine", "in the middle", "i18n is hard"]
    )
    func leavesOtherWordsAlone(input: String) {
        #expect(TextTidy.capitalisePronounI(input) == input)
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

    /// A full stop after code is wrong, and dictating code is a use this product serves.
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
