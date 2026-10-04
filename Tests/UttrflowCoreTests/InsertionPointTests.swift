import Testing

@testable import UttrflowCore

@Suite("InsertionPoint")
struct InsertionPointTests {
    @Test("does not know where the caret is when the field would not say")
    func unknownWithoutText() {
        #expect(InsertionPoint.sentenceState(before: nil) == .unknown)
        #expect(InsertionPoint.unknown.sentenceState == .unknown)
    }

    @Test(
        "an empty field, or one holding only spaces, is the start of the text",
        arguments: ["", "   ", " \t "])
    func startOfText(preceding: String) {
        #expect(InsertionPoint.sentenceState(before: preceding) == .startOfText)
    }

    @Test(
        "a sentence end or a line break before the caret starts a sentence",
        arguments: [
            "Ship it.", "Ship it. ", "Really?", "Go!\t", "first line\n", "first line\n   ", "Done.\n\n",
            "\n\n",
        ]
    )
    func startOfSentence(preceding: String) {
        #expect(InsertionPoint.sentenceState(before: preceding) == .startOfSentence)
    }

    @Test(
        "a new line opened by LF, CRLF or CR starts a sentence, with or without a marker on it",
        arguments: ["\n", "\r\n", "\r"])
    func everyLineBreakStartsASentence(newline: String) {
        #expect(InsertionPoint.sentenceState(before: "previous line" + newline) == .startOfSentence)
        #expect(InsertionPoint.sentenceState(before: "previous line" + newline + "- ") == .startOfText)
        #expect(InsertionPoint.sentenceState(before: "previous line" + newline + "and then") == .midSentence)
    }

    @Test(
        "any other last mark leaves the caret mid-sentence",
        arguments: [
            "The build failed because", "The build failed because ", "milk, eggs,", "wait",
            "Great work! 🎉 but", "Done. and then", "He said \"go.\" and left",
        ]
    )
    func midSentence(preceding: String) {
        #expect(InsertionPoint.sentenceState(before: preceding) == .midSentence)
    }

    @Test(
        "known dotted abbreviations keep a caret mid-sentence",
        arguments: [
            "Bring snacks, e.g. ", "This is i.e. ", "Apples vs. ", "Fruit, etc. ", "Meet at 3 p.m. ",
            "Call at 9 a.m. ",
        ]
    )
    func abbreviationContinuesSentence(preceding: String) {
        #expect(InsertionPoint.sentenceState(before: preceding) == .midSentence)
    }

    @Test(
        "a sentence end before closing quotes, brackets or trailing emoji opens the next sentence",
        arguments: [
            "She said \"Go home.\" ", "She said ‘Go home.’ ", "(See the notes.) ",
            "[See the notes!] ", "Great work! 🎉 ", "Amazing. 👩🏽‍💻 ", "Wait… ",
        ])
    func sentenceEndBeforeClosersAndEmojiStartsSentence(preceding: String) {
        #expect(InsertionPoint.sentenceState(before: preceding) == .startOfSentence)
    }

    @Test(
        "ordinary terminal punctuation starts a sentence while punctuation mid-sentence does not",
        arguments: [
            ("Done. ", true), ("Really? ", true), ("Go! ", true), ("3.14 is pi", false),
            ("Wait… ", true), ("Great work 🎉 ", false), ("Great work! 🎉 and then", false),
        ]
    )
    func terminalPunctuationAndMidSentenceControls(example: (String, Bool)) {
        #expect(
            InsertionPoint.sentenceState(before: example.0)
                == (example.1 ? .startOfSentence : .midSentence))
    }

    /// A marker is typed but not written: the caret after one opens the line, whatever the marker is.
    @Test(
        "a caret after a list, quote or heading marker opens the line",
        arguments: [
            "- ", "* ", "\u{2022} ", "1. ", "2) ", "# ", "## ", "> ", "\"", "(", "[",
            "notes\n- ", "notes\n1. ", "Done.\n\n- ",
        ]
    )
    func markerOpensTheLine(preceding: String) {
        #expect(InsertionPoint.sentenceState(before: preceding) == .startOfText)
    }

    /// The bullet and the numbered item are two items of one list and must be read the same way.
    @Test("reads a bulleted and a numbered item alike")
    func listMarkersAgree() {
        #expect(
            InsertionPoint.sentenceState(before: "- ")
                == InsertionPoint.sentenceState(before: "1. "))
    }

    /// Only the marker the line opens with is a marker; the same character inside a line is a word's.
    @Test(
        "reads words written after the marker as the middle of a sentence",
        arguments: ["- the migration", "1. the migration ", "# Incident log", "-5 degrees ", "well - "])
    func wordsAfterTheMarkerContinue(preceding: String) {
        #expect(InsertionPoint.sentenceState(before: preceding) == .midSentence)
    }

    @Test("keeps both sides of the caret exactly as given")
    func keepsText() {
        let point = InsertionPoint(precedingText: "before ", followingText: " after")
        #expect(point.precedingText == "before ")
        #expect(point.followingText == " after")
        #expect(point.sentenceState == .midSentence)
    }

    @Test("bounds what a reader keeps either side of the caret")
    func limits() {
        #expect(InsertionPoint.precedingLimit == 300)
        #expect(InsertionPoint.followingLimit == 100)
    }

    @Test("a word after another word is padded with one leading space")
    func leadingSpaceAfterAWord() {
        let point = InsertionPoint(precedingText: "I went to the", followingText: "")
        #expect(point.paddedBoundary(for: "store", in: .plain) == " store")
    }

    @Test("a word after a comma is padded with one leading space")
    func leadingSpaceAfterComma() {
        let point = InsertionPoint(precedingText: "Hello,", followingText: "")
        #expect(point.paddedBoundary(for: "world", in: .plain) == " world")
    }

    @Test(
        "punctuation and clitics attach to preceding text without a generated space",
        arguments: [
            ", then", ".", ";", ":", "!", "?", ")", "]", "}", "\"", "”", "’",
            "'s", "n't", "'re", "'ll", "'d", "'ve", "'m",
        ]
    )
    func punctuationAndCliticsAttach(dictated: String) {
        for preceding in ["hello", "7", " "] {
            let point = InsertionPoint(precedingText: preceding, followingText: nil)
            #expect(point.paddedBoundary(for: dictated, in: .plain) == dictated)
        }
    }

    @Test("a word after a space already brings its own join, so no leading space is added")
    func leadingSpaceAfterASpace() {
        let point = InsertionPoint(precedingText: "Hello ", followingText: "world")
        #expect(point.paddedBoundary(for: "big", in: .plain) == "big ")
    }

    @Test("a word at the start of a new line adds no leading space")
    func leadingSpaceAtLineStart() {
        let point = InsertionPoint(precedingText: "first line\n", followingText: "")
        #expect(point.paddedBoundary(for: "store", in: .plain) == "store")
    }

    @Test("a word in an empty field adds no leading space")
    func leadingSpaceInEmptyField() {
        let point = InsertionPoint(precedingText: "", followingText: "")
        #expect(point.paddedBoundary(for: "Hello", in: .plain) == "Hello")
    }

    @Test("a word after an opening bracket belongs inside the brackets, so no leading space")
    func leadingSpaceAfterOpeningBracket() {
        let point = InsertionPoint(precedingText: "(", followingText: "stuff)")
        #expect(point.paddedBoundary(for: "world", in: .plain) == "world ")
    }

    @Test(
        "a straight quote opens only at the start of text or after a boundary",
        arguments: ["\"", "'", "say \"", "say '", "say (\"", "say ('"])
    func leadingSpaceAfterOpeningStraightQuote(preceding: String) {
        let point = InsertionPoint(precedingText: preceding, followingText: "")
        #expect(point.paddedBoundary(for: "world", in: .plain) == "world")
    }

    @Test(
        "a straight quote after a word closes the quote and separates the next word",
        arguments: ["said \"hi\"", "said 'hi'", "it'"])
    func leadingSpaceAfterClosingStraightQuote(preceding: String) {
        let point = InsertionPoint(precedingText: preceding, followingText: "")
        #expect(point.paddedBoundary(for: "world", in: .plain) == " world")
    }

    @Test("a word before another word is padded with one trailing space")
    func trailingSpaceBeforeAWord() {
        let point = InsertionPoint(precedingText: "", followingText: "world")
        #expect(point.paddedBoundary(for: "Hello", in: .plain) == "Hello ")
    }

    @Test("a word before a stop adds the leading space but no trailing one")
    func trailingSpaceBeforeStop() {
        let point = InsertionPoint(precedingText: "Hello world", followingText: ".")
        #expect(point.paddedBoundary(for: "again", in: .plain) == " again")
    }

    @Test("a field that refused its text leaves the dictated words untouched")
    func precedingTextIsNilLeavesTextAlone() {
        let point = InsertionPoint(precedingText: nil, followingText: nil)
        #expect(point.paddedBoundary(for: "Hello", in: .plain) == "Hello")
    }

    @Test("a field that reports an empty preceding text also leaves the dictated words untouched")
    func precedingTextIsEmptyLeavesLeadingAlone() {
        let point = InsertionPoint(precedingText: "", followingText: "world")
        #expect(point.paddedBoundary(for: "Hello", in: .plain) == "Hello ")
    }

    /// Mid-word, both rules fire and the dictated word gets a space at each edge.
    @Test("a mid-word caret adds a space at each edge, by definition of the rules")
    func midWordCaretAddsBothSpaces() {
        let point = InsertionPoint(precedingText: "Hello wo", followingText: "rld")
        #expect(point.paddedBoundary(for: "big", in: .plain) == " big ")
    }

    @Test("text that already starts with whitespace needs no extra leading space")
    func dictatedTextLeadingWhitespaceIsKept() {
        let point = InsertionPoint(precedingText: "Hello,", followingText: "")
        #expect(point.paddedBoundary(for: "  world", in: .plain) == "  world")
    }

    @Test("text that already ends with whitespace needs no extra trailing space")
    func dictatedTextTrailingWhitespaceIsKept() {
        let point = InsertionPoint(precedingText: "", followingText: "world")
        #expect(point.paddedBoundary(for: "Hello  ", in: .plain) == "Hello  ")
    }

    @Test("a blank dictated text is returned unchanged")
    func blankDictatedTextIsUnchanged() {
        let point = InsertionPoint(precedingText: "Hello", followingText: "world")
        #expect(point.paddedBoundary(for: "   ", in: .plain) == "   ")
    }

    @Test(
        "text ending in any script's sentence mark starts a sentence",
        arguments: Array(SentenceMarks.ends) + [SentenceMarks.ellipsis])
    func everySentenceMarkStartsASentence(mark: Character) {
        #expect(InsertionPoint.sentenceState(before: "word" + String(mark) + " ") == .startOfSentence)
    }

    @Test("an abbreviation's stop still continues the sentence beside the other scripts' marks")
    func abbreviationStillContinues() {
        #expect(
            InsertionPoint.sentenceState(before: "\u{0928}\u{092E}\u{0938}\u{094D}\u{0924}\u{0947} Dr. ")
                == .midSentence)
    }

    @Test(
        "the caret right after any comment marker is the start of the text",
        arguments: ["// ", "/// ", "/* ", "/** ", "/*\n * ", " * ", "# ", "-- ", "\"\"\"", "' "])
    func commentMarkerStartsText(preceding: String) {
        #expect(InsertionPoint.sentenceState(before: preceding) == .startOfText)
    }
}
