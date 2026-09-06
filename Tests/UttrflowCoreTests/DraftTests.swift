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

    @Test("tells a list mark from the other layout marks")
    func listMarks() {
        #expect(Draft.Word("\n- ").isListMark && Draft.Word("\n- ").isLayoutMark)
        #expect(Draft.Word("- ").isListMark && Draft.Word("- ").isLayoutMark)
        #expect(!Draft.Word("\n\n").isListMark && Draft.Word("\n\n").isLayoutMark)
        #expect(!Draft.Word("-").isListMark && !Draft.Word("-").isLayoutMark)
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
        #expect(Draft(words: words.map { Draft.Word($0) }).text == expected)
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
                    text: "um", heard: "um", confidence: 1, state: .removed(by: pass),
                    edits: [Draft.Word.Edit(by: pass, kind: .removed, from: "um", to: "")])
            ])
        #expect(draft.presentIndices == [1, 2])
        #expect(!draft.words[0].isPresent)
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
        #expect(Draft.Word("\n").isLayoutMark)
        #expect(Draft.Word("\n- ").isLayoutMark)
        #expect(!Draft.Word("hello").isLayoutMark)
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
        #expect(draft.words == ["Okay", "so,", "um,", "quick"].map { Draft.Word($0) })
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
private struct ShoutPass: CleaningPass {
    static let id: PassID = "shout"
    func apply(_ draft: Draft) -> Draft {
        var draft = draft
        for index in draft.presentIndices {
            draft.replace(at: index, with: draft.words[index].text.uppercased(), by: Self.id)
        }
        return draft
    }
}

/// Removes the first present word.
private struct DropFirstPass: CleaningPass {
    static let id: PassID = "dropFirst"
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
}
