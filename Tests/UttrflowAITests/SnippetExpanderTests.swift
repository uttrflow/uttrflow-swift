import Foundation
import UttrflowCore
import Testing

@testable import UttrflowAI

extension SnippetExpansion {
    /// Whether anything fired.
    var didExpand: Bool { !applied.isEmpty }
}

// MARK: - Fixtures

/// The expansion the standard "my address" snippet carries.
private let address = "Flat 402, Example Residences, Sample Road, Bengaluru 560001"

/// The snippets the design's list shows, plus the two that overlap.
private func standardExpander() -> SnippetExpander {
    SnippetExpander(snippets: [
        makeSnippet(trigger: "my address", expansion: address),
        makeSnippet(trigger: "my work address", expansion: "Level 4, 12 Example Street"),
        makeSnippet(trigger: "sign off", expansion: "Thanks, Avery"),
        makeSnippet(trigger: "pr", expansion: "pull request"),
    ])
}

/// The expander's matching, ordering, quoting and reporting.
@Suite("Expanding what the user actually said")
struct SnippetExpanderTests {

    // MARK: Matching on words, not characters

    @Test(
        "a snippet whose trigger says a spoken command never fires, whatever the pass order",
        arguments: [
            ("new line", "first new line second"), ("sign off full stop", "Thanks, sign off full stop"),
        ])
    func commandTriggerNeverFires(trigger: String, said: String) {
        let expander = SnippetExpander(snippets: [makeSnippet(trigger: trigger, expansion: "Kind regards")])
        #expect(!expander.expand(said).didExpand)
    }

    @Test(
        "finds the trigger through whatever the tidier did to it",
        arguments: [
            ("my address", address),
            // A full stop the tidier added, and a capital it added, are not the trigger.
            ("My address.", "\(address)."),
            ("MY ADDRESS!", "\(address)!"),
            ("Send it to my address, please.", "Send it to \(address), please."),
            // A comma inside the trigger is a speaker pausing, not a different phrase.
            ("my,  address", address),
        ]
    )
    func punctuationTolerance(transcript: String, expected: String) {
        #expect(standardExpander().expand(transcript).text == expected)
    }

    @Test("carries sentence-start casing into the expansion and preserves its saved text")
    func sentenceStartExpansion() {
        let expander = SnippetExpander(snippets: [
            makeSnippet(trigger: "brb", expansion: "be right back"),
            makeSnippet(trigger: "ok", expansion: "Okay, sounds good."),
            makeSnippet(trigger: "idk", expansion: "123 ready\nnext line"),
            makeSnippet(trigger: "dollar", expansion: "$12 ready"),
        ])

        #expect(expander.expand("Brb.").text == "Be right back.")
        #expect(expander.expand("Before. Brb.").text == "Before. Be right back.")
        #expect(expander.expand("Ok.").text == "Okay, sounds good.")
        #expect(expander.expand("Idk.").text == "123 ready\nnext line.")
        #expect(expander.expand("Dollar.").text == "$12 ready.")
    }

    @Test(
        "drops only an adjacent tidy mark already present at the expansion end",
        arguments: [
            ("ok.", "Okay, sounds good."),
            ("ok?", "Okay, sounds good?"),
            ("ok!", "Okay, sounds good!"),
            ("ok:", "Okay, sounds good:"),
            ("ok,", "Okay, sounds good,"),
            ("ok? next", "Okay, sounds good? next"),
            ("ok. next", "Okay, sounds good. next"),
        ]
    )
    func avoidsDuplicateTerminalPunctuation(transcript: String, expected: String) {
        let expander = SnippetExpander(snippets: [makeSnippet(trigger: "ok", expansion: "Okay, sounds good.")]
        )

        #expect(expander.expand(transcript).text == expected)
    }

    @Test(
        "keeps tidy punctuation after expansions with internal punctuation",
        arguments: [
            ("my email", "my email.", "me@example.com", "me@example.com."),
            ("my email", "my email, then call me", "me@example.com", "me@example.com, then call me"),
            ("phone", "phone.", "Call 555.1234 now", "Call 555.1234 now."),
            ("version", "version, please", "Version 2.5 is out", "Version 2.5 is out, please"),
        ]
    )
    func preservesTidyPunctuationAfterInternalMarks(
        trigger: String, transcript: String, expansion: String, expected: String
    ) {
        let expander = SnippetExpander(snippets: [makeSnippet(trigger: trigger, expansion: expansion)])

        #expect(expander.expand(transcript).text == expected)
    }

    @Test("detects terminal punctuation before trailing whitespace")
    func duplicateTerminalPunctuationBeforeWhitespace() {
        let expander = SnippetExpander(snippets: [
            makeSnippet(trigger: "ok", expansion: "Okay, sounds good. ")
        ])

        #expect(expander.expand("ok.").text == "Okay, sounds good. ")
    }

    @Test(
        "matches trigger words joined by written joiners or spaces",
        arguments: [
            ("sign-off", "sign off", "Regards"),
            ("sign-off", "Sign-off", "Regards"),
            ("e-mail", "e-mail", "Email"),
            ("e-mail", "e mail", "Email"),
            ("and/or", "and/or", "Either"),
            ("and/or", "and or", "Either"),
        ]
    )
    func writtenJoinersMatch(trigger: String, transcript: String, expansion: String) {
        let result = SnippetExpander(snippets: [makeSnippet(trigger: trigger, expansion: expansion)])
            .expand("Use \(transcript) now.")

        #expect(result.text == "Use \(expansion) now.")
    }

    @Test("a word trigger does not match inside a longer hyphenated word")
    func wordTriggerDoesNotMatchInsideJoinedWord() {
        let expander = SnippetExpander(snippets: [makeSnippet(trigger: "ops", expansion: "Operations")])

        #expect(expander.expand("dev-ops-team").text == "dev-ops-team")
        #expect(expander.expand("ops team").text == "Operations team")
    }

    @Test("puts the expansion exactly where the words were, and leaves the rest alone")
    func replacesOnlyTheWords() {
        let result = standardExpander().expand("Before. My address. After.")
        #expect(result.text == "Before. \(address). After.")
    }

    @Test("fires as many times as the trigger was said")
    func firesRepeatedly() {
        let result = standardExpander().expand("pr and pr")
        #expect(result.text == "Pull request and pull request")
        #expect(result.applied.count == 2)
    }

    // MARK: The longest trigger wins

    @Test("prefers the longer trigger when two of them fit")
    func longestWins() {
        let result = standardExpander().expand("Send it to my work address.")
        #expect(result.text == "Send it to Level 4, 12 Example Street.")
        #expect(result.applied.count == 1)
    }

    @Test("still takes the shorter one when the longer is not what was said")
    func shorterWinsWhenItIsTheOnlyFit() {
        #expect(standardExpander().expand("my address").text == address)
    }

    /// Two triggers starting on the same word is the case the ordering exists for.
    @Test("the trigger that claims more of the sentence wins")
    func longestWinsAtTheSameStart() {
        let expander = SnippetExpander(snippets: [
            makeSnippet(trigger: "meeting link", expansion: "SHORT"),
            makeSnippet(trigger: "meeting link for today", expansion: "LONG"),
        ])
        #expect(expander.expand("Share the meeting link for today.").text == "Share the LONG.")
    }

    /// Snippet order must not decide anything, or a save that reorders the file changes expansions.
    @Test("the answer does not depend on what order the snippets were in")
    func orderOfSnippetsDoesNotMatter() {
        let snippets = [
            makeSnippet(trigger: "meeting link", expansion: "SHORT"),
            makeSnippet(trigger: "meeting link for today", expansion: "LONG"),
            makeSnippet(trigger: "pr", expansion: "pull request"),
            makeSnippet(trigger: "add", expansion: "Adobe"),
        ]
        let transcript = "Share the meeting link for today, add a pr."
        let forwards = SnippetExpander(snippets: snippets).expand(transcript).text
        let backwards = SnippetExpander(snippets: snippets.reversed()).expand(transcript).text
        #expect(forwards == backwards)
        #expect(forwards == "Share the LONG, Adobe a pull request.")
    }

    /// The store refuses duplicate triggers; a hand-edited file can hold them, and the matcher stays pure.
    @Test("a duplicated trigger in a hand-edited file resolves the same way every time")
    func duplicateTriggersAreDecidedOnce() {
        let first = makeSnippet(trigger: "pr", expansion: "first")
        let second = makeSnippet(trigger: "PR.", expansion: "second")
        #expect(SnippetExpander(snippets: [first, second]).expand("a pr").text == "a first")
        #expect(SnippetExpander(snippets: [second, first]).expand("a pr").text == "a second")
    }

    // MARK: Never expanding what the user is quoting

    @Test("says nothing twice when the transcript already contains the expansion")
    func quotingIsLeftAlone() {
        let result = standardExpander().expand("My address is \(address), as you know.")
        #expect(!result.didExpand)
        #expect(result.text == result.original)
    }

    @Test("notices the quotation through a difference of case or spacing")
    func quotingIsRecognisedLoosely() {
        let expander = SnippetExpander(snippets: [
            makeSnippet(trigger: "sign off", expansion: "Thanks,  Avery")
        ])
        #expect(!expander.expand("sign off with thanks, Avery").didExpand)
    }

    @Test("an expansion inside a longer word does not suppress its trigger")
    func quotedSubstringDoesNotSuppressExpansion() {
        let expander = SnippetExpander(snippets: [
            makeSnippet(trigger: "sign off", expansion: "Thanks, Avery")
        ])
        let result = expander.expand("The thanks, Averyly sign off was timely.")
        #expect(result.text == "The thanks, Averyly Thanks, Avery was timely.")
        #expect(result.applied.count == 1)
    }

    /// One snippet being quoted must not stop the others.
    @Test("only the quoted snippet is held back")
    func quotingIsPerSnippet() {
        let result = standardExpander().expand("pr, and my address is \(address).")
        #expect(result.text == "Pull request, and my address is \(address).")
    }

    // MARK: Bounded

    @Test("a snippet whose text contains its own trigger expands once and stops")
    func selfReferenceTerminates() {
        let expander = SnippetExpander(snippets: [
            makeSnippet(trigger: "sign off", expansion: "Thanks, Avery — sign off")
        ])
        let result = expander.expand("Please sign off.")
        #expect(result.text == "Please Thanks, Avery — sign off.")
        #expect(result.applied.count == 1)
    }

    @Test("a snippet that is exactly its own trigger does nothing at all")
    func selfReferenceThatIsAlreadyQuoted() {
        let expander = SnippetExpander(snippets: [makeSnippet(trigger: "loop", expansion: "loop")])
        #expect(!expander.expand("start loop end").didExpand)
    }

    @Test("a snippet that repeats its trigger does not multiply")
    func selfReferenceThatGrows() {
        let expander = SnippetExpander(snippets: [
            makeSnippet(trigger: "loop", expansion: "loop loop")
        ])
        let result = expander.expand("start loop end")
        #expect(result.text == "start loop loop end")
        #expect(result.applied.count == 1)
    }

    /// Two snippets naming each other is what a depth counter would guard; a single pass needs none.
    @Test("two snippets that name each other expand once each")
    func mutualReferenceTerminates() {
        let expander = SnippetExpander(snippets: [
            makeSnippet(trigger: "ping", expansion: "pong please"),
            makeSnippet(trigger: "pong", expansion: "ping please"),
        ])
        let result = expander.expand("ping and pong")
        #expect(result.text == "Pong please and ping please")
        #expect(result.applied.count == 2)
    }

    // MARK: What it reports

    @Test("reports every firing, with the words that were actually said")
    func theReport() {
        let snippet = makeSnippet(trigger: "my address", expansion: address)
        let result = SnippetExpander(snippets: [snippet]).expand("My address.")

        #expect(result.didExpand)
        #expect(result.original == "My address.")
        #expect(
            result.applied == [
                AppliedSnippet(snippetID: snippet.id, matched: "My address", expansion: address)
            ])
        #expect(result.usedSnippetIDs == [snippet.id])
    }

    /// Undo is restoring one string. Anything cleverer is a second chance to be wrong.
    @Test("keeps the original, so undo has nothing to recompute")
    func undoIsTheOriginal() {
        let result = standardExpander().expand("My address.")
        #expect(result.original == "My address.")
        #expect(result.text != result.original)
    }

    @Test("a transcript nothing fired in reports nothing and is handed back unchanged")
    func nothingHappened() {
        let result = standardExpander().expand("Nothing to see here.")
        #expect(!result.didExpand)
        #expect(result.usedSnippetIDs.isEmpty)
        #expect(result.text == "Nothing to see here.")
    }

    // MARK: Snippets that could never fire

    @Test(
        "a snippet that could never fire is not allowed to try",
        arguments: [
            // No words: it would otherwise match at every position.
            makeSnippet(trigger: "!!!", expansion: "something"),
            // No text: it would otherwise replace words with silence.
            makeSnippet(trigger: "quiet", expansion: "  "),
        ]
    )
    func unusableSnippetsAreDropped(snippet: Snippet) {
        let expander = SnippetExpander(snippets: [snippet])
        #expect(expander.expand("quiet please !!!").text == "quiet please !!!")
    }

    @Test("a user with no snippets gets their words back untouched")
    func noSnippets() {
        let result = SnippetExpander(snippets: []).expand("Anything at all.")
        #expect(result.text == "Anything at all.")
        #expect(!result.didExpand)
    }

    @Test("a transcript with no words in it is not something to expand")
    func noWords() {
        #expect(standardExpander().expand("...").text == "...")
        #expect(standardExpander().expand("").text.isEmpty)
    }

    // MARK: The caret marker

    @Test("inserts the body without its marker and reports where the caret ends")
    func caretMarker() {
        let expander = SnippetExpander(snippets: [
            makeSnippet(trigger: "greeting", expansion: "Dear {caret},\nThanks")
        ])
        let result = expander.expand("Then greeting now")
        #expect(result.text == "Then Dear ,\nThanks now")
        #expect(result.caret == "Then Dear ".utf16.count)
        #expect(result.applied.map(\.expansion) == ["Dear ,\nThanks"], "history never sees a marker")
    }

    @Test("a marker typed with a backslash is written literally and places nothing")
    func escapedMarker() {
        let expander = SnippetExpander(snippets: [
            makeSnippet(trigger: "syntax", expansion: "type \\{caret} here")
        ])
        let result = expander.expand("syntax")
        #expect(result.text == "Type {caret} here")
        #expect(result.caret == nil)
    }

    @Test("the first marked firing places the caret, and further markers are dropped")
    func firstCaretWins() {
        let expander = SnippetExpander(snippets: [
            makeSnippet(trigger: "alpha", expansion: "a{caret}b{caret}c"),
            makeSnippet(trigger: "beta", expansion: "x{caret}y"),
        ])
        let result = expander.expand("alpha beta")
        #expect(result.text == "Abc Xy")
        #expect(result.caret == 1)
    }

    @Test("a body that is only a marker cannot fire")
    func markerOnlyIsUnusable() {
        #expect(!makeSnippet(trigger: "blank", expansion: "{caret}").isUsable)
    }
}
