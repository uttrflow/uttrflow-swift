import NaturalLanguage
import Testing
import UttrflowCore

@Suite("Lexical class")
struct LexicalClassTests {
    @Test("reads a word's class by its index in the sentence")
    func byIndex() {
        #expect(LexicalClass.tag(ofWordAt: 1, in: ["they", "ship", "today"]) == .verb)
        #expect(LexicalClass.tag(ofWordAt: 1, in: ["the", "ship", "sails"]) == .noun)
    }

    @Test("reads every word's class at once, as the index reader does")
    func everyIndex() {
        let words = ["they", "ship", "today"]
        let oneByOne = words.indices.map { LexicalClass.tag(ofWordAt: $0, in: words) }
        #expect(LexicalClass.tags(ofWords: words) == oneByOne)
        #expect(LexicalClass.tags(ofWords: []).isEmpty)
    }

    @Test("gives no class outside the words")
    func outside() {
        #expect(LexicalClass.tag(ofWordAt: 3, in: ["the", "ship"]) == nil)
        #expect(LexicalClass.tag(ofWordAt: -1, in: ["the", "ship"]) == nil)
        let text = "the ship"
        #expect(LexicalClass.tag(at: text.endIndex, in: text) == nil)
    }

    @Test("lists every word with its class and skips punctuation")
    func everyWord() {
        let tagged = LexicalClass.tags(in: "The ship sails, today.")
        #expect(tagged.map(\.word) == ["The", "ship", "sails", "today"])
        #expect(tagged.first?.tag == .determiner)
    }

    @Test("knows an English word in any case and not an invented term")
    func knownEnglishWord() {
        #expect(LexicalClass.isKnownEnglishWord("Inbox"))
        #expect(LexicalClass.isKnownEnglishWord("downloads"))
        #expect(!LexicalClass.isKnownEnglishWord("pgvector"))
        #expect(!LexicalClass.isKnownEnglishWord("Zorvane"))
    }
}
