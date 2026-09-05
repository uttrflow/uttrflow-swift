import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("ContractionsPass")
struct ContractionsPassTests {
    private let sut = ContractionsPass()

    @Test(
        "puts the apostrophe back into a contraction that is a contraction and nothing else",
        arguments: [
            ("dont forget the meeting", "don't forget the meeting"),
            ("she doesnt agree", "she doesn't agree"),
            ("we didnt ship", "we didn't ship"),
            ("cant reproduce it", "can't reproduce it"),
            ("it wont build", "it won't build"),
            ("that isnt right", "that isn't right"),
            ("they arent here", "they aren't here"),
            ("it wasnt me", "it wasn't me"),
            ("we werent told", "we weren't told"),
            ("it hasnt landed", "it hasn't landed"),
            ("we havent started", "we haven't started"),
            ("he hadnt asked", "he hadn't asked"),
            ("we couldnt tell", "we couldn't tell"),
            ("you shouldnt worry", "you shouldn't worry"),
            ("that wouldnt help", "that wouldn't help"),
            ("ive read it", "I've read it"),
            ("im on the way", "I'm on the way"),
            ("youre right", "you're right"),
            ("theyre late", "they're late"),
            ("weve shipped it", "we've shipped it"),
            ("thats the plan", "that's the plan"),
        ]
    )
    func repairs(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "keeps the case the word was heard in, and the punctuation around it",
        arguments: [
            ("Dont forget", "Don't forget"),
            ("Cant we ship?", "Can't we ship?"),
            ("\"dont\"", "\"don't\""),
            ("dont, then", "don't, then"),
        ]
    )
    func keepsShape(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    /// "Ill" and "Id" are ordinary words in lower case, so only the capital says the speaker meant "I".
    @Test(
        "repairs Ill and Id only where the capital says which word it is",
        arguments: [
            ("Ill be there", "I'll be there"),
            ("Id rather not", "I'd rather not"),
            ("he was ill all week", "he was ill all week"),
            ("the id of the row", "the id of the row"),
        ]
    )
    func capitalisedOnly(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    /// Each of these is a word in its own right, so repairing it would put words the speaker never said.
    @Test(
        "leaves a word whose contraction is a guess",
        arguments: [
            "its own colour", "we wed in june", "shes here", "were going", "hell of a week",
        ]
    )
    func leavesTheAmbiguous(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    @Test("records which pass rewrote the word, and what it read before")
    func provenance() {
        let draft = sut.apply(Draft(text: "dont stop"))
        #expect(draft.text == "don't stop")
        #expect(draft.words[0].state == .replaced(by: ContractionsPass.id, from: "dont"))
        #expect(draft.words[1].state == .kept)
    }
}
