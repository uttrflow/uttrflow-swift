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
            ("youll see", "you'll see"),
            ("theyll come", "they'll come"),
            ("theyve left", "they've left"),
            ("youve won", "you've won"),
            ("i wouldve gone", "i would've gone"),
            ("i couldve called", "i could've called"),
            ("i shouldve stayed", "i should've stayed"),
            ("i mightve known", "i might've known"),
            ("mustnt go", "mustn't go"),
            ("neednt worry", "needn't worry"),
            ("yall come back", "y'all come back"),
            ("be there at five oclock", "be there at five o'clock"),
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

    /// An acronym carries a capital past its first letter, which no heard contraction does.
    @Test(
        "leaves an acronym alone rather than reading it as a contraction",
        arguments: ["reset the user ID", "an IM from her", "the IDs we issued", "DONT in caps"]
    )
    func leavesAcronyms(input: String) {
        #expect(cleaned(input, by: sut) == input)
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

    @Test(
        "restores it's only when the next word makes the possessive reading impossible",
        arguments: [
            ("its been a long day", "it's been a long day"),
            ("its going to rain", "it's going to rain"),
            ("its a long day", "it's a long day"),
            ("its not ready", "it's not ready"),
            ("Its been a long day", "It's been a long day"),
        ]
    )
    func resolvesItsContraction(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "resolves ambiguous plurals only when the next word identifies the contraction",
        arguments: [
            ("whats up", "what's up"),
            ("Whos there?", "Who's there?"),
            ("wheres the key", "where's the key"),
            ("wheres my bag", "where's my bag"),
            ("hows it going", "how's it going"),
        ]
    )
    func resolvesContextualContraction(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test("keeps plural nouns whose spellings also look like contractions")
    func preservesAmbiguousPlurals() {
        for input in ["the whats and whys", "the whos who", "the wheres and whys", "the hows and whys"] {
            #expect(cleaned(input, by: sut) == input)
        }
    }

    @Test("keeps its as a possessive and preserves ordinary plurals")
    func preservesPossessivesAndPlurals() {
        for input in [
            "its own colour", "its blue cover", "the dogs bowl is empty", "the teams results are in",
        ] {
            #expect(cleaned(input, by: sut) == input)
        }
    }

    @Test("records which pass rewrote the word, and what it read before")
    func provenance() {
        let draft = sut.apply(Draft(text: "dont stop"))
        #expect(draft.text == "don't stop")
        #expect(draft.words[0].state == .replaced(by: ContractionsPass.id, from: "dont"))
        #expect(draft.words[1].state == .kept)
    }

    @Test("does not state addsNoWords, because the apostrophe cuts a contraction into new letter words")
    func apostropheAddsLetterWords() {
        #expect(ContractionsPass().apply(Draft(text: "its a")).text == "it's a")
        #expect(!ContractionsPass.laws.contains(.addsNoWords))
    }
}
