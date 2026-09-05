import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("FirstWordPass")
struct FirstWordPassTests {
    private let sut = FirstWordPass()

    @Test(
        "capitalises the start of every sentence",
        arguments: [
            ("hello there", "Hello there"),
            ("hello. there", "Hello. There"),
            ("hello! there? okay", "Hello! There? Okay"),
            ("42 things", "42 things"),
            ("\"hello\" there", "\"Hello\" there"),
            ("", ""),
        ]
    )
    func capitalisesSentences(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "capitalises the pronoun I, alone or contracted",
        arguments: [
            ("i think so", "I think so"),
            ("well i think", "Well I think"),
            ("i", "I"),
            ("i, therefore", "I, therefore"),
            ("well i'll go", "Well I'll go"),
            ("it is fine", "It is fine"),
            ("i18n is hard", "I18n is hard"),
            ("the i18n work", "The i18n work"),
        ]
    )
    func capitalisesPronoun(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test("starts a sentence after a paragraph or a bullet, but not after a plain line break")
    func layout() {
        let paragraph = Draft(
            words: ["hello", "\n\n", "there", "\n- ", "milk", "\n", "eggs"].map { Draft.Word($0) })
        #expect(sut.apply(paragraph).text == "Hello\n\nThere\n- Milk\neggs")
    }

    @Test(
        "lowercases the first word for a caret mid-sentence, leaving I and acronyms alone",
        arguments: [
            ("Hello there. Again", "hello there. Again"),
            ("I think", "I think"),
            ("I'll go", "I'll go"),
            ("API keys", "API keys"),
            ("\"Hello\"", "\"hello\""),
            ("42 things", "42 things"),
        ]
    )
    func lowercasesFirstWord(input: String, expected: String) {
        #expect(cleaned(input, by: FirstWordPass(policy: .lowercase)) == expected)
    }

    @Test("records a changed word against this pass")
    func provenance() {
        let draft = sut.apply(Draft(text: "hello there"))
        #expect(draft.words[0].state == .replaced(by: FirstWordPass.id, from: "hello"))
        #expect(draft.words[1].state == .kept)
    }
}
