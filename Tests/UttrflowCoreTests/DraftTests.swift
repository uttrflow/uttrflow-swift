import Testing

@testable import UttrflowCore

@Suite("Draft")
struct DraftTests {
    private let pass: PassID = "test"

    @Test("splits plain text on whitespace into kept words at full confidence")
    func splitsText() {
        let draft = Draft(text: "  hello   there\nfriend ")
        #expect(draft.words.map(\.text) == ["hello", "there", "friend"])
        #expect(draft.words.allSatisfy { $0.state == .kept && $0.confidence == 1 && $0.heard == $0.text })
    }

    @Test(
        "keeps every ellipsis inside its token as written",
        arguments: [
            "Ah...the...um...the invoice is...ah...overdue",
            "wait\u{2026} we should\u{2026} move the\u{2026}the end\u{2026}",
            "e.g. https://example.com/a...b hello...world",
            "open ~/projects/.../Sources and pages 1...5 or src/a...b",
        ])
    func keepsEllipsesInTokens(text: String) {
        let draft = Draft(text: text)
        #expect(draft.words.map(\.text) == text.split(separator: " ").map(String.init))
        #expect(draft.text == text)
    }

    @Test(
        "keeps line breaks between words as layout marks when asked, and round-trips the text",
        arguments: [
            ("hello there", ["hello", "there"], "hello there"),
            ("line one\nline two", ["line", "one", "\n", "line", "two"], "line one\nline two"),
            ("one\n\ntwo", ["one", "\n\n", "two"], "one\n\ntwo"),
            (
                "we need:\n- milk\n- eggs", ["we", "need:", "\n- ", "milk", "\n- ", "eggs"],
                "we need:\n- milk\n- eggs"
            ),
            ("\n  hello \t there\n\n", ["hello", "there"], "hello there"),
            ("", [], ""),
        ]
    )
    func keepsLineBreaks(text: String, words: [String], rendered: String) {
        let draft = Draft(keepingLineBreaks: text)
        #expect(draft.words.map(\.text) == words)
        #expect(draft.text == rendered)
    }

    @Test(
        "reads a line opening with a dash, a bullet or an asterisk as a list item, the first line included",
        arguments: [
            (
                "- the tent\n- the stove", ["- ", "the", "tent", "\n- ", "the", "stove"],
                "- the tent\n- the stove"
            ),
            (
                "packing\n\n• tent\n* stove", ["packing", "\n\n- ", "tent", "\n- ", "stove"],
                "packing\n\n- tent\n- stove"
            ),
            (
                "a - b\n-5 degrees\n-", ["a", "-", "b", "\n", "-5", "degrees", "\n", "-"],
                "a - b\n-5 degrees\n-"
            ),
        ]
    )
    func readsBullets(text: String, words: [String], rendered: String) {
        let draft = Draft(keepingLineBreaks: text)
        #expect(draft.words.map(\.text) == words)
        #expect(draft.text == rendered)
        for word in draft.words where word.text.hasSuffix("- ") {
            #expect(word.isLayoutMark && word.isListMark)
        }
    }

    @Test("reads numbered lines as list items")
    func readsNumberedItems() {
        let draft = Draft(keepingLineBreaks: "1. call mom\n2. pay rent\n3. book the flight")

        #expect(
            draft.words.map(\.text)
                == ["1. ", "call", "mom", "\n2. ", "pay", "rent", "\n3. ", "book", "the", "flight"])
        #expect(draft.text == "1. call mom\n2. pay rent\n3. book the flight")
        #expect(draft.words.filter(\.isListMark).count == 3)
    }

    @Test("tells a list mark from the other layout marks")
    func listMarks() {
        #expect(
            Draft.Word("\n- ", evidence: .unknown).isListMark
                && Draft.Word("\n- ", evidence: .unknown).isLayoutMark)
        #expect(
            Draft.Word("- ", evidence: .unknown).isListMark
                && Draft.Word("- ", evidence: .unknown).isLayoutMark)
        #expect(
            !Draft.Word("\n\n", evidence: .unknown).isListMark
                && Draft.Word("\n\n", evidence: .unknown).isLayoutMark)
        #expect(
            !Draft.Word("-", evidence: .unknown).isListMark
                && !Draft.Word("-", evidence: .unknown).isLayoutMark)
        #expect(
            Draft.Word("\n1. ", evidence: .unknown).isListMark
                && Draft.Word("\n1. ", evidence: .unknown).isLayoutMark)
        #expect(
            Draft.Word("\n21. ", evidence: .unknown).isListMark
                && Draft.Word("\n21. ", evidence: .unknown).isLayoutMark)
        #expect(
            !Draft.Word("\n. ", evidence: .unknown).isListMark
                && !Draft.Word("\n1.", evidence: .unknown).isListMark)
    }

    @Test("joins the words with single spaces")
    func joinsWords() {
        #expect(Draft(text: "hello there").text == "hello there")
        #expect(Draft(text: "").text == "")
    }

    @Test(
        "renders a layout mark without spaces around it",
        arguments: [
            (["hello", "\n", "there"], "hello\nthere"),
            (["one", "\n\n", "two"], "one\n\ntwo"),
            (["we", "need", "\n- ", "milk", "\n- ", "eggs"], "we need\n- milk\n- eggs"),
            (["\n", "hello"], "\nhello"),
        ]
    )
    func rendersLayoutMarks(words: [String], expected: String) {
        #expect(Draft(words: words.map { Draft.Word($0, evidence: .unknown) }).text == expected)
    }

    @Test("drops a removed word from the text but keeps it in the record")
    func removedWords() {
        var draft = Draft(text: "um hello there")
        draft.remove(at: 0, by: pass)
        #expect(draft.text == "hello there")
        #expect(draft.originalText == "um hello there")
        #expect(
            draft.removed == [
                Draft.Word(
                    text: "um", heard: "um", evidence: .unknown, state: .removed(by: pass),
                    edits: [Draft.Word.Edit(by: pass, kind: .removed, from: "um", to: "")])
            ])
        #expect(draft.presentIndices == [1, 2])
        #expect(!draft.words[0].isPresent)
    }

    // MARK: - Carrying the marks of a word that goes

    /// The recogniser hangs a sentence's mark on whatever word it ended on, filler or not.
    @Test(
        "moves the marks of a removed word onto the words that stay",
        arguments: [
            ("shipping today, uh?", 2, "shipping today?"),
            ("that is amazing uh!", 3, "that is amazing!"),
            ("ready; uh?", 1, "ready?"),
            // A comma is the pause the word stood in, so it goes with the word.
            ("the build, um, failed", 2, "the build, failed"),
            // Nothing stands before it, so there is nowhere for the mark to go.
            ("uh? yes", 0, "yes"),
            // An ellipsis is a pause too, so it never lands as a full stop.
            ("we should um... move", 2, "we should move"),
            ("we should um\u{2026} move", 2, "we should move"),
            ("is it um...? yes", 2, "is it? yes"),
        ]
    )
    func carriesMarksOnRemoval(input: String, index: Int, expected: String) {
        var draft = Draft(text: input)
        draft.remove(at: index, by: pass, carryingMarks: true)
        #expect(draft.text == expected)
    }

    /// A currency or percent sign is part of the amount, so it leaves with it rather than landing on a neighbour.
    @Test(
        "takes an amount's own sign away with it and still carries the sentence's mark",
        arguments: [
            ("the total is $40 50", 3, "the total is 50"),
            ("costs \u{20AC}5 6", 1, "costs 6"),
            ("costs \u{20B9}5 6", 1, "costs 6"),
            ("the fee is 40% 50%", 3, "the fee is 50%"),
            ("was it 40%?", 2, "was it?"),
            ("a rate of 5\u{2030} 6\u{2030}", 3, "a rate of 6\u{2030}"),
            ("a rate of 5\u{2031} 6\u{2031}", 3, "a rate of 6\u{2031}"),
            ("set it to 40\u{00B0} 50\u{00B0}", 3, "set it to 50\u{00B0}"),
            ("ticket #5 #6", 1, "ticket #6"),
        ]
    )
    func dropsAnAmountsOwnSign(input: String, index: Int, expected: String) {
        var draft = Draft(text: input)
        draft.remove(at: index, by: pass, carryingMarks: true)
        #expect(draft.text == expected)
    }

    /// Only a number owns its sign; on a word the same mark is the sentence's and still moves on.
    @Test("carries a sign forward when the removed word is not a number")
    func carriesASignOffAWord() {
        var draft = Draft(text: "see #uh todo")
        draft.remove(at: 1, by: pass, carryingMarks: true)
        #expect(draft.text == "see #todo")
    }

    @Test("leaves the marks where they were when the caller does not ask for them")
    func plainRemovalCarriesNothing() {
        var draft = Draft(text: "shipping today, uh?")
        draft.remove(at: 2, by: pass)
        #expect(draft.text == "shipping today,")
    }

    @Test("moves an opening mark forward, onto the word the removed one stood before")
    func carriesAnOpeningMarkForward() {
        var draft = Draft(text: "he said \"uh we shipped")
        draft.remove(at: 2, by: pass, carryingMarks: true)
        #expect(draft.text == "he said \"we shipped")
    }

    @Test("moves only the opening mark forward when asked for opening marks, leaving the closing one behind")
    func carriesOnlyTheOpeningMark() {
        var draft = Draft(text: "alpha @comma. beta")
        draft.remove(at: 1, by: pass, carryingOpeningMarks: true)
        #expect(draft.text == "alpha @beta")
    }

    /// A mark belongs to the line it was spoken on, and the word before the break ended its own.
    @Test("does not carry a mark across a line break")
    func doesNotCarryAcrossABreak() {
        var draft = Draft(words: [
            Draft.Word("today", evidence: .unknown), Draft.Word("\n", evidence: .unknown),
            Draft.Word("uh?", evidence: .unknown),
        ])
        draft.remove(at: 2, by: pass, carryingMarks: true)
        #expect(draft.text == "today\n")
    }

    @Test("rides the mark past a word removed before it to the one that stays")
    func carriesPastAnotherRemoval() {
        var draft = Draft(text: "today um uh!")
        draft.remove(at: 1, by: pass, carryingMarks: true)
        draft.remove(at: 2, by: pass, carryingMarks: true)
        #expect(draft.text == "today!")
    }

    @Test("owes the moved mark to the pass that removed the word")
    func carryingIsRecordedAsAnEdit() {
        var draft = Draft(text: "shipping today, uh?")
        draft.remove(at: 2, by: pass, carryingMarks: true)
        #expect(draft.words[1].state == .replaced(by: pass, from: "today,"))
        #expect(draft.words[2].state == .removed(by: pass))
    }

    @Test("records what a replaced word read before, and which pass changed it")
    func replacedWords() {
        var draft = Draft(text: "hello there")
        draft.replace(at: 0, with: "Hello", by: pass)
        #expect(draft.text == "Hello there")
        #expect(draft.words[0].state == .replaced(by: pass, from: "hello"))
        #expect(draft.words[0].heard == "hello")
        #expect(draft.words[0].isPresent)
    }

    @Test("a word two passes rewrote is owed to both of them, from the word as heard")
    func chainedRewrites() {
        var draft = Draft(text: "dont")
        draft.replace(at: 0, with: "don't", by: "contractions")
        draft.replace(at: 0, with: "Don't", by: "firstWord")
        #expect(draft.text == "Don't")
        #expect(
            draft.words[0].edits == [
                Draft.Word.Edit(by: "contractions", kind: .replaced, from: "dont", to: "don't"),
                Draft.Word.Edit(by: "firstWord", kind: .replaced, from: "don't", to: "Don't"),
            ])
    }

    @Test("a removed word cannot be brought back by a later pass rewriting it")
    func replacingARemovedWordChangesNothing() {
        var draft = Draft(text: "um hello")
        draft.remove(at: 0, by: "fillers")
        draft.replace(at: 0, with: "Um", by: "firstWord")
        #expect(draft.text == "hello")
        #expect(draft.words[0].state == .removed(by: "fillers"))
        #expect(draft.words[0].edits.count == 1)
    }

    @Test("records nothing when a replacement changes nothing")
    func unchangedReplacement() {
        var draft = Draft(text: "hello")
        draft.replace(at: 0, with: "hello", by: pass)
        #expect(draft.words[0].state == .kept)
    }

    @Test("marks an inserted word as never heard")
    func insertedWords() {
        var draft = Draft(text: "hello there")
        draft.insert(",", at: 1, by: pass)
        #expect(draft.text == "hello , there")
        #expect(draft.originalText == "hello there")
        #expect(draft.words[1].state == .inserted(by: pass))
        #expect(draft.words[1].heard.isEmpty)
    }

    @Test("knows a layout mark from a word")
    func layoutMarks() {
        #expect(Draft.Word("\n", evidence: .unknown).isLayoutMark)
        #expect(Draft.Word("\n- ", evidence: .unknown).isLayoutMark)
        #expect(!Draft.Word("hello", evidence: .unknown).isLayoutMark)
    }

    @Test("takes the recogniser's confidences when its words are the text's words")
    func usesTimedWords() {
        let transcription = Transcription(
            text: "hello there",
            segments: [
                TranscriptionSegment(
                    text: "hello there", start: .zero, end: .seconds(1),
                    words: [
                        TranscribedWord(text: " hello", confidence: 0.9),
                        TranscribedWord(text: "there", confidence: 0.2),
                    ]
                )
            ])
        let draft = Draft(transcription: transcription)
        #expect(draft.words.map(\.text) == ["hello", "there"])
        #expect(draft.words.map(\.confidence) == [0.9, 0.2])
        #expect(draft.confidencesAreReal)
    }

    @Test("keeps the confidences when the timed words differ from the text only in spacing")
    func usesTimedWordsWithWhisperKitSpacing() {
        let transcription = Transcription(
            text: "Okay so, um, quick",
            segments: [
                TranscriptionSegment(
                    text: " Okay so, um, quick", start: .zero, end: .seconds(1),
                    words: [
                        TranscribedWord(text: " Okay", confidence: 0.9),
                        TranscribedWord(text: " so,", confidence: 0.8),
                        TranscribedWord(text: " um,", confidence: 0.3),
                        TranscribedWord(text: " quick", confidence: 0.7),
                    ]
                )
            ])
        let draft = Draft(transcription: transcription)
        #expect(draft.words.map(\.text) == ["Okay", "so,", "um,", "quick"])
        #expect(draft.words.map(\.heard) == ["Okay", "so,", "um,", "quick"])
        #expect(draft.words.map(\.confidence) == [0.9, 0.8, 0.3, 0.7])
        #expect(draft.confidencesAreReal)
    }

    @Test("gives a word split across timed pieces the lowest confidence among them")
    func lowestConfidenceAcrossPieces() {
        let transcription = Transcription(
            text: "hello there",
            segments: [
                TranscriptionSegment(
                    text: "hel lo there", start: .zero, end: .seconds(1),
                    words: [
                        TranscribedWord(text: "hel", confidence: 0.9),
                        TranscribedWord(text: "lo th", confidence: 0.4),
                        TranscribedWord(text: "ere", confidence: 0.6),
                    ]
                )
            ])
        let draft = Draft(transcription: transcription)
        #expect(draft.words.map(\.text) == ["hello", "there"])
        #expect(draft.words.map(\.confidence) == [0.4, 0.4])
        #expect(draft.confidencesAreReal)
    }

    @Test("splits the text when a segment reports no words")
    func fallsBackWithoutTimedWords() {
        let transcription = Transcription(
            text: "hello there again",
            segments: [
                TranscriptionSegment(
                    text: "hello there", start: .zero, end: .seconds(1),
                    words: [
                        TranscribedWord(text: "hello", confidence: 0.9),
                        TranscribedWord(text: "there", confidence: 0.2),
                    ]
                ),
                TranscriptionSegment(text: "again", start: .seconds(1), end: .seconds(2)),
            ])
        let draft = Draft(transcription: transcription)
        #expect(draft.words.map(\.text) == ["hello", "there", "again"])
        #expect(draft.words.map(\.confidence) == [1, 1, 1])
        #expect(!draft.confidencesAreReal)
    }

    @Test("splits the text when a timed word is missing, and says the confidences are stand-ins")
    func fallsBackWhenWordsDisagree() {
        let transcription = Transcription(
            text: "Okay so, um, quick",
            segments: [
                TranscriptionSegment(
                    text: " Okay so, quick", start: .zero, end: .seconds(1),
                    words: [
                        TranscribedWord(text: " Okay", confidence: 0.9),
                        TranscribedWord(text: " so,", confidence: 0.8),
                        TranscribedWord(text: " quick", confidence: 0.7),
                    ]
                )
            ])
        let draft = Draft(transcription: transcription)
        #expect(draft.words == ["Okay", "so,", "um,", "quick"].map { Draft.Word($0, evidence: .unknown) })
        #expect(!draft.confidencesAreReal)
    }

    @Test("says the confidences are stand-ins when there are no timed words at all")
    func fallsBackWithoutSegments() {
        #expect(!Draft(transcription: Transcription(text: "hello")).confidencesAreReal)
        #expect(!Draft(transcription: Transcription(text: "")).confidencesAreReal)
        #expect(!Draft(text: "hello").confidencesAreReal)
    }

    @Test("names a pass from a string literal")
    func passIdentifiers() {
        let id: PassID = "fillers"
        #expect(id.rawValue == "fillers")
        #expect(id.description == "fillers")
        #expect(id == PassID(rawValue: "fillers"))
    }
}

/// Upper-cases every present word.
private struct ShoutPass: PieceCleaningPass {
    static let id: PassID = "shout"
    static let laws: Set<PassLaw> = []
    func apply(_ draft: Draft) -> Draft {
        var draft = draft
        for index in draft.presentIndices {
            draft.replace(at: index, with: draft.words[index].text.uppercased(), by: Self.id)
        }
        return draft
    }
}

/// Removes the first present word.
private struct DropFirstPass: PieceCleaningPass {
    static let id: PassID = "dropFirst"
    static let laws: Set<PassLaw> = []
    func apply(_ draft: Draft) -> Draft {
        var draft = draft
        if let first = draft.presentIndices.first { draft.remove(at: first, by: Self.id) }
        return draft
    }
}

@Suite("CleaningPipeline")
struct CleaningPipelineTests {
    @Test("runs its passes in order over the same draft")
    func runsInOrder() {
        let pipeline = CleaningPipeline(passes: [DropFirstPass(), ShoutPass()])
        let draft = pipeline.run(Draft(text: "um hello there"))
        #expect(draft.text == "HELLO THERE")
        #expect(draft.words[0].state == .removed(by: "dropFirst"))
        #expect(draft.words[1].state == .replaced(by: "shout", from: "hello"))
    }

    @Test("names its passes in order")
    func ids() {
        #expect(CleaningPipeline(passes: [ShoutPass(), DropFirstPass()]).ids == ["shout", "dropFirst"])
        #expect(ShoutPass().id == "shout")
    }

    @Test("leaves named passes out without disturbing the rest")
    func without() {
        let pipeline = CleaningPipeline(passes: [DropFirstPass(), ShoutPass()]).without(["dropFirst"])
        #expect(pipeline.ids == ["shout"])
        #expect(pipeline.run(Draft(text: "um hello")).text == "UM HELLO")
    }

    @Test("does nothing with no passes")
    func empty() {
        #expect(CleaningPipeline(passes: []).run(Draft(text: "hello")).text == "hello")
    }

    @Test("romanising keeps each Devanagari word's origin and leaves Latin words Latin")
    func romanisingKeepsOrigin() {
        let draft = Draft(romanising: Transcription(text: "मैं meeting में था"))
        #expect(draft.text == "main meeting mein tha")
        #expect(draft.words.indices.map(draft.isHindi(at:)) == [true, false, true, true])
        #expect(draft.originalText == "main meeting mein tha")
    }
}

@Suite("Draft word timing")
struct DraftTimingTests {
    @Test("reads the silence between two timed words")
    func pauseBetweenTimedWords() {
        let words = [
            TranscribedWord(text: "done", confidence: 1, start: .zero, end: .milliseconds(400)),
            TranscribedWord(
                text: "next", confidence: 1, start: .milliseconds(1_300), end: .milliseconds(1_600)),
        ]
        let draft = Draft(
            transcription: Transcription(
                text: "done next",
                segments: [
                    TranscriptionSegment(text: "done next", start: .zero, end: .seconds(2), words: words)
                ]))
        #expect(draft.pause(before: 1) == .milliseconds(900))
        #expect(draft.pause(before: 0) == nil)
    }

    @Test("knows no pause for words the recogniser did not time")
    func untimed() {
        #expect(Draft(text: "done next").pause(before: 1) == nil)
    }
}
