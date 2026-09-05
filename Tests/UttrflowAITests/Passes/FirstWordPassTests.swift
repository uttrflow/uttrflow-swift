import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("FirstWordPass")
struct FirstWordPassTests {
    private let sut = FirstWordPass()

    private func fromCaret(
        _ text: String, state: InsertionPoint.SentenceState, onScreen: [String] = []
    ) -> String {
        cleaned(text, by: FirstWordPass(policy: .fromInsertionPoint, state: state, onScreen: onScreen))
    }

    private func asSpoken(_ text: String, heard: String) -> String {
        cleaned(text, by: FirstWordPass(policy: .asSpoken, heard: heard))
    }

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
            ("well i\u{2019}m late", "Well I\u{2019}m late"),
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
        "lower-cases the first word for a caret mid-sentence, and a later sentence still starts with a capital",
        arguments: [
            ("Hello there. Again", "hello there. Again"),
            ("The build failed.", "the build failed."),
            ("\"Hello\"", "\"hello\""),
            ("\"Quoted\" words.", "\"quoted\" words."),
            ("42 things", "42 things"),
            ("", ""),
        ]
    )
    func lowersMidSentence(input: String, expected: String) {
        #expect(fromCaret(input, state: .midSentence) == expected)
    }

    @Test(
        "gives the first word a capital anywhere but mid-sentence",
        arguments: [InsertionPoint.SentenceState.startOfText, .startOfSentence, .unknown]
    )
    func capitalElsewhere(state: InsertionPoint.SentenceState) {
        #expect(fromCaret("the build failed.", state: state) == "The build failed.")
        #expect(fromCaret("The build failed.", state: state) == "The build failed.")
    }

    @Test(
        "keeps the capital of I, its contractions and an acronym mid-sentence",
        arguments: [
            "I think so.", "I'll be there.", "I\u{2019}m late.", "API returns JSON.", "NASA said so.",
            "USB-C only.",
        ]
    )
    func exemptions(text: String) {
        #expect(fromCaret(text, state: .midSentence) == text)
    }

    @Test("always capital gives the first word a capital whatever the caret says")
    func alwaysCapital() {
        let pass = FirstWordPass(policy: .alwaysCapital, state: .midSentence)
        #expect(cleaned("hello there", by: pass) == "Hello there")
        #expect(cleaned("42 things", by: pass) == "42 things")
        #expect(cleaned("", by: pass) == "")
    }

    @Test("as spoken copies the case the first word was heard in, past any filler before it")
    func asSpoken() {
        #expect(asSpoken("Total revenue", heard: "um total revenue") == "total revenue")
        #expect(asSpoken("Total revenue", heard: "total revenue") == "total revenue")
        #expect(asSpoken("total revenue", heard: "Total revenue") == "Total revenue")
        #expect(asSpoken("Total, revenue", heard: "total revenue") == "total, revenue")
        #expect(asSpoken("\"Total\" revenue", heard: "total revenue") == "\"total\" revenue")
    }

    @Test("as spoken leaves a first word the model changed, or that has no letters, alone")
    func asSpokenOnlyForTheSameWord() {
        #expect(asSpoken("Sum of revenue", heard: "total revenue") == "Sum of revenue")
        #expect(asSpoken("42 things", heard: "42 things") == "42 things")
        #expect(asSpoken("", heard: "total") == "")
    }

    @Test("as spoken reads the draft's own heard words when no transcript is given")
    func asSpokenFromTheDraft() {
        let pass = FirstWordPass(policy: .asSpoken)
        var draft = Draft(text: "um total revenue")
        draft.remove(at: 0, by: FillersPass.id)
        draft.replace(at: 1, with: "Total", by: "test")
        #expect(pass.apply(draft).text == "total revenue")
        #expect(cleaned("Total revenue", by: pass) == "Total revenue")
    }

    @Test("keeps a first word that reappears capitalised later in the output, off a sentence start")
    func keepsNameSeenAgainInOutput() {
        #expect(
            fromCaret("John said the build failed, so John fixed it.", state: .midSentence)
                == "John said the build failed, so John fixed it.")
        #expect(
            fromCaret("Because the build failed. Because of that.", state: .midSentence)
                == "because the build failed. Because of that.")
    }

    @Test("keeps a first word that the screen shows capitalised, in the title or around the caret")
    func keepsNameSeenOnScreen() {
        let text = "John said the build failed."
        #expect(fromCaret(text, state: .midSentence, onScreen: ["Chat with John"]) == text)
        #expect(fromCaret(text, state: .midSentence, onScreen: ["", "Ask (John) tomorrow."]) == text)
        #expect(
            fromCaret(text, state: .midSentence, onScreen: ["Notes"]) == "john said the build failed.")
    }

    @Test(
        "lowers a common first word mid-sentence, and keeps I and an acronym, whatever the screen shows",
        arguments: [
            ("Because the build failed.", "because the build failed."),
            ("I'll fix it.", "I'll fix it."), ("API returns JSON.", "API returns JSON."),
        ]
    )
    func lowersOrKeepsWithScreen(text: String, expected: String) {
        let screen = ["Because - Notes", "ok. Because"]
        #expect(fromCaret(text, state: .midSentence, onScreen: screen) == expected)
    }

    @Test("sights a name off a sentence start only, and not in a text capitalised throughout")
    func looksLikeName() {
        #expect(FirstWordPass.looksLikeName("John", in: ["so John said"]))
        #expect(FirstWordPass.looksLikeName("john", in: ["so \"John\" said"]))
        #expect(!FirstWordPass.looksLikeName("John", in: ["so john said"]))
        #expect(!FirstWordPass.looksLikeName("John", in: ["John said", "ok. John said", "ok\nJohn said"]))
        #expect(!FirstWordPass.looksLikeName("John", in: ["Mail - John Smith"]))
        #expect(!FirstWordPass.looksLikeName("...", in: ["so ... said"]))
        #expect(!FirstWordPass.looksLikeName("John", in: []))
    }

    @Test("names an exemption exactly: a lone capital or a run of two or more")
    func keepsCapital() {
        #expect(FirstWordPass.keepsCapital("I"))
        #expect(FirstWordPass.keepsCapital("I'd"))
        #expect(FirstWordPass.keepsCapital("\"I'd\""))
        #expect(FirstWordPass.keepsCapital("USB-C"))
        #expect(!FirstWordPass.keepsCapital("A"))
        #expect(!FirstWordPass.keepsCapital("It"))
        #expect(!FirstWordPass.keepsCapital("Ice"))
    }

    @Test("records a changed word against this pass, once")
    func provenance() {
        let draft = sut.apply(Draft(text: "hello there"))
        #expect(draft.words[0].state == .replaced(by: FirstWordPass.id, from: "hello"))
        #expect(draft.words[1].state == .kept)
        let unchanged = FirstWordPass(policy: .fromInsertionPoint, state: .midSentence).apply(
            Draft(text: "hello"))
        #expect(unchanged.words[0].state == .kept)
    }
}
