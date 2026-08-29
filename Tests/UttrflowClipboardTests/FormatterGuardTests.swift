import Testing

@testable import UttrflowClipboard

/// The gate that makes formatting affordable. Two halves: it must let a formatter do the
/// things formatters legitimately do, and it must catch the three failures the
/// specification names — a dropped line, a changed string literal, a normalised number.
@Suite("D6, D7 · the round-trip guard")
struct FormatterGuardTests {
    // MARK: What a formatter is allowed to do

    @Test(
        "reformatting that changes only how the code is written is accepted",
        arguments: [
            // Reindented.
            ("func a(){\nlet x=1\n}", "func a() {\n    let x = 1\n}"),
            // A brace moved.
            ("if a\n{\nb()\n}", "if a {\n    b()\n}"),
            // A trailing comma added.
            ("[1, 2, 3]", "[\n    1,\n    2,\n    3,\n]"),
            // Quote style changed, contents identical.
            ("let a = 'hello'", "let a = \"hello\""),
            // A long line wrapped.
            ("call(one, two, three)", "call(\n  one,\n  two,\n  three\n)"),
            // A semicolon dropped.
            ("let x = 1;", "let x = 1"),
            // A comment rewrapped across lines.
            ("// one two three four", "// one two\n// three four"),
        ])
    func acceptsRewriting(_ each: (String, String)) {
        #expect(FormatterGuard.isFaithful(each.1, to: each.0))
    }

    @Test("and identical text is trivially faithful")
    func identical() {
        #expect(FormatterGuard.isFaithful("let x = 1", to: "let x = 1"))
        #expect(FormatterGuard.isFaithful("", to: ""))
    }

    // MARK: The three the specification names

    /// "silently drops a line"
    @Test("a dropped line is caught")
    func droppedLine() {
        let before = "let a = 1\nlet b = 2\nlet c = 3"
        let after = "let a = 1\nlet c = 3"

        #expect(!FormatterGuard.isFaithful(after, to: before))
    }

    /// "changes a string literal"
    @Test("a changed string literal is caught")
    func changedLiteral() {
        #expect(!FormatterGuard.isFaithful("let a = \"goodbye\"", to: "let a = \"hello\""))
        #expect(
            !FormatterGuard.isFaithful(
                "connect(\"prod\")", to: "connect(\"staging\")"))
    }

    /// "normalises a number" — the one that looks harmless and is not.
    @Test(
        "a normalised number is caught",
        arguments: [
            ("let a = 1.0", "let a = 1"),
            ("let a = 0.50", "let a = 0.5"),
            ("let a = 1_000", "let a = 1000"),
            ("let a = 0x10", "let a = 16"),
        ])
    func normalisedNumber(_ each: (String, String)) {
        #expect(!FormatterGuard.isFaithful(each.1, to: each.0))
    }

    // MARK: The rest of the ways it could go wrong

    @Test("a deleted comment is caught, even though a rewrapped one is not")
    func deletedComment() {
        let before = "// remember the timeout\nlet a = 1"

        #expect(!FormatterGuard.isFaithful("let a = 1", to: before))
        #expect(FormatterGuard.isFaithful("// remember the\n// timeout\nlet a = 1", to: before))
    }

    @Test("a renamed identifier is caught")
    func renamed() {
        #expect(!FormatterGuard.isFaithful("let b = 1", to: "let a = 1"))
    }

    @Test("reordered lines are caught, because order is what the code says")
    func reordered() {
        #expect(!FormatterGuard.isFaithful("let b = 2\nlet a = 1", to: "let a = 1\nlet b = 2"))
    }

    @Test("an inserted line is caught")
    func inserted() {
        #expect(!FormatterGuard.isFaithful("let a = 1\nlet b = 2", to: "let a = 1"))
    }

    /// Truncation is what a formatter does when it fails halfway, and it is the failure
    /// that looks most like success.
    @Test("output cut short is caught")
    func truncated() {
        let before = "func a() {\n    doTheThing()\n    andTheOther()\n}"

        #expect(!FormatterGuard.isFaithful("func a() {\n    doTheThing()", to: before))
    }

    /// A formatter returning nothing at all is the clearest failure there is, and must not
    /// read as "the code is now empty".
    @Test("empty output against real input is caught")
    func emptied() {
        #expect(!FormatterGuard.isFaithful("", to: "let a = 1"))
    }

    /// Words inside a string are content, so changing the punctuation around them is not
    /// a change — but changing the words is.
    @Test("punctuation inside a string may move; the words may not")
    func stringContents() {
        #expect(FormatterGuard.isFaithful("print(\"a, b\")", to: "print(\"a , b\")"))
        #expect(!FormatterGuard.isFaithful("print(\"a c\")", to: "print(\"a b\")"))
    }
}

/// D5 — what may be run, and what may never be.
@Suite("D5 · which formatters are trusted")
struct KnownFormatterTests {
    @Test("every language a formatter claims resolves back to that formatter")
    func languagesResolve() {
        for formatter in KnownFormatter.allCases {
            for language in formatter.languages {
                #expect(KnownFormatter.forLanguage(language) != nil, "\(language)")
            }
        }
    }

    /// An allowlist, not a search. The alternative is executing whatever happens to be on
    /// PATH under a familiar name, and this feature hands it everything the user is about
    /// to paste into production.
    @Test("a language with no trusted formatter has none, rather than a guess")
    func noGuessing() {
        #expect(KnownFormatter.forLanguage(.shell) == nil)
        #expect(KnownFormatter.forLanguage(.sql) == nil)
        #expect(KnownFormatter.forLanguage(.java) == nil)
    }

    /// The code being formatted is the user's and may contain anything at all. On a
    /// command line that becomes a command, so it goes in on standard input and every
    /// argument is a constant written here.
    ///
    /// Pinned exactly rather than by shape: "looks like a flag" would have accepted
    /// `rustfmt`'s `stdout`, and would go on accepting anything that happened to start
    /// with a dash. Naming them means adding one is a deliberate edit to this list.
    @Test("every argument is a constant, so none can carry the clip")
    func argumentsAreConstants() {
        let expected: [KnownFormatter: [String]] = [
            .swiftFormat: ["format"],
            .prettier: ["--stdin-filepath", "clip.ts"],
            .black: ["-q", "-"],
            .rustfmt: ["--emit", "stdout"],
            .gofmt: [],
        ]

        for formatter in KnownFormatter.allCases {
            #expect(formatter.arguments == expected[formatter], "\(formatter.rawValue)")
        }
    }

    /// A search of `PATH` would execute whatever a shell plugin or a project's `.envrc`
    /// had prepended to it, on everything the user is about to paste.
    @Test("formatters are looked for in fixed directories, never on PATH")
    func fixedDirectories() {
        #expect(!SystemCodeFormatter.directories.isEmpty)
        #expect(SystemCodeFormatter.directories.allSatisfy { $0.hasPrefix("/") })
    }

    /// This runs while somebody is waiting on a paste, and a program that has hung must
    /// not take the panel with it.
    @Test("a formatter is given a bounded time to answer")
    func bounded() {
        #expect(KnownFormatter.timeout > 0)
        #expect(KnownFormatter.timeout <= 5)
    }
}
