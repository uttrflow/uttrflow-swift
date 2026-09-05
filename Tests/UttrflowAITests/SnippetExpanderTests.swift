import Foundation
import UttrflowCore
import Testing

@testable import UttrflowAI

extension SnippetExpansion {
    /// Whether anything fired.
    var didExpand: Bool { !applied.isEmpty }
}

// MARK: - Fixtures

private let address = "Flat 402, Example Residences, Sample Road, Bengaluru 560001"

/// The snippets the design's list shows, plus the two that overlap.
private func standardExpander() -> SnippetExpander {
    SnippetExpander(snippets: [
        makeSnippet(trigger: "my address", expansion: address),
        makeSnippet(trigger: "my work address", expansion: "Level 4, Vaswani Presidio"),
        makeSnippet(trigger: "sign off", expansion: "Thanks, Naveen"),
        makeSnippet(trigger: "pr", expansion: "pull request"),
    ])
}

@Suite("Expanding what the user actually said")
struct SnippetExpanderTests {

    // MARK: Matching on words, not characters

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

    @Test("puts the expansion exactly where the words were, and leaves the rest alone")
    func replacesOnlyTheWords() {
        let result = standardExpander().expand("Before. My address. After.")
        #expect(result.text == "Before. \(address). After.")
    }

    @Test("fires as many times as the trigger was said")
    func firesRepeatedly() {
        let result = standardExpander().expand("pr and pr")
        #expect(result.text == "pull request and pull request")
        #expect(result.applied.count == 2)
    }

    // MARK: The longest trigger wins

    @Test("prefers the longer trigger when two of them fit")
    func longestWins() {
        let result = standardExpander().expand("Send it to my work address.")
        #expect(result.text == "Send it to Level 4, Vaswani Presidio.")
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

    /// The order the snippets arrive in must not decide anything, or the same words
    /// would expand differently after a save reordered the file.
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

    /// One trigger, two snippets, is a question with no right answer. The store refuses
    /// to create it; a hand-edited file could, and the matcher must still be a function.
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
            makeSnippet(trigger: "sign off", expansion: "Thanks,  Naveen")
        ])
        #expect(!expander.expand("sign off with thanks, Naveen").didExpand)
    }

    /// One snippet being quoted must not stop the others.
    @Test("only the quoted snippet is held back")
    func quotingIsPerSnippet() {
        let result = standardExpander().expand("pr, and my address is \(address).")
        #expect(result.text == "pull request, and my address is \(address).")
    }

    // MARK: Bounded

    @Test("a snippet whose text contains its own trigger expands once and stops")
    func selfReferenceTerminates() {
        let expander = SnippetExpander(snippets: [
            makeSnippet(trigger: "sign off", expansion: "Thanks, Naveen — sign off")
        ])
        let result = expander.expand("Please sign off.")
        #expect(result.text == "Please Thanks, Naveen — sign off.")
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

    /// Two snippets pointing at each other is the case a depth counter would have had
    /// to catch. A single pass over the original has nothing to catch.
    @Test("two snippets that name each other expand once each")
    func mutualReferenceTerminates() {
        let expander = SnippetExpander(snippets: [
            makeSnippet(trigger: "ping", expansion: "pong please"),
            makeSnippet(trigger: "pong", expansion: "ping please"),
        ])
        let result = expander.expand("ping and pong")
        #expect(result.text == "pong please and ping please")
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
}
