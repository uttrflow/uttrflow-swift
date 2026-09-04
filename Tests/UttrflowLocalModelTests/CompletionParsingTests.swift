import Testing

@testable import UttrflowLocalModel

/// What the model's reply is allowed to become, decided without loading a model.
@Suite("Completion parsing")
struct CompletionParsingTests {
    @Test("Lines that extend what was typed are kept in order, once each, whatever marks the model added.")
    func extendingLinesAreKept() {
        let reply = "```\n1. git checkout main\n- git commit -m\n* git checkout main\ngit c\n```"
        #expect(MLXCandidateScorer.parse(reply, typed: "git c") == ["git checkout main", "git commit -m"])
    }

    @Test("A line quoting the prompt back is not a completion, however it begins.")
    func promptEchoesAreDropped() {
        let reply = "Notes, field AXTextArea, continue this text:\nnavigate to the settings"
        #expect(MLXCandidateScorer.parse(reply, typed: "n") == ["navigate to the settings"])
        let headings = """
            on my way. Continue this line:
            on screen around the field: Priya
            on my way, Lines this person wrote here before
            on my way, be there at 7
            """
        #expect(MLXCandidateScorer.parse(headings, typed: "on my") == ["on my way, be there at 7"])
    }

    @Test("A continuation that loops on itself is dropped rather than drawn across the screen.")
    func repetitionIsDropped() {
        let looping = "sr" + String(repeating: " -  sr", count: 40)
        #expect(MLXCandidateScorer.parse(looping + "\nsrc/main.swift", typed: "sr") == ["src/main.swift"])
        #expect(MLXCandidateScorer.isDegenerate(" - sr - sr - sr - sr - sr - sr"))
        #expect(!MLXCandidateScorer.isDegenerate(" -l"))
        #expect(!MLXCandidateScorer.isDegenerate("toring the data in the table for the next run"))
    }

    @Test("A continuation the length of a paragraph is not the rest of a line.")
    func paragraphsAreDropped() {
        let paragraph = String(repeating: "word ", count: 60)
        #expect(MLXCandidateScorer.isDegenerate(paragraph))
        #expect(MLXCandidateScorer.parse("st" + paragraph, typed: "st").isEmpty)
    }

    @Test("Nothing is made of one typed character, since a guess about nothing is noise.")
    func oneCharacterIsTooLittle() {
        #expect(MLXCandidateScorer.minimumTypedLength == 2)
        #expect("s".trimmingCharacters(in: .whitespaces).count < MLXCandidateScorer.minimumTypedLength)
        #expect("ls".trimmingCharacters(in: .whitespaces).count >= MLXCandidateScorer.minimumTypedLength)
    }
}
