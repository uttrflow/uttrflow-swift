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
            draft.removed == [Draft.Word(text: "um", heard: "um", confidence: 1, state: .removed(by: pass))])
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
    }

    @Test("splits the text when the timed words disagree with it")
    func fallsBackWhenWordsDisagree() {
        let transcription = Transcription(
            text: "hello there",
            segments: [
                TranscriptionSegment(
                    text: "hello", start: .zero, end: .seconds(1),
                    words: [TranscribedWord(text: "hello", confidence: 0.9)])
            ])
        #expect(Draft(transcription: transcription).words == [Draft.Word("hello"), Draft.Word("there")])
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
