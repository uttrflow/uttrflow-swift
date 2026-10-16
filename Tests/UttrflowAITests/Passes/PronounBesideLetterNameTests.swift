import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("The pronoun I beside a word that is also a letter name")
struct PronounBesideLetterNameTests {
    private func cleaned(_ text: String) -> String {
        CleaningPipeline.standard.run(Draft(text: text)).text
    }

    @Test(
        "is capitalised after you",
        arguments: [
            ("thank you i will call", "Thank you I will call."),
            ("see you i think", "See you I think."),
            ("where are you i am here", "Where are you I am here?"),
        ])
    func afterYou(input: String, expected: String) {
        #expect(cleaned(input) == expected)
    }

    @Test(
        "is capitalised beside see, oh and why",
        arguments: [
            ("when i see you", "When I see you."),
            ("oh i know", "Oh I know."),
            ("why i think so", "Why I think so."),
        ])
    func besideOtherEverydayWords(input: String, expected: String) {
        #expect(cleaned(input) == expected)
    }

    @Test("a spelled run that holds an i is still joined")
    func spelledRunKeepsItsLetters() {
        #expect(cleaned("the a p i is down") == "The API is down.")
    }
}
