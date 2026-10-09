import Testing

@testable import UttrflowDictionary

@Suite("The ordinary words that really are said alike, and the collisions that are not")
struct HomophoneTests {
    /// The reading the phonetic candidates exist for: two ordinary words, one sound, one of them the wrong spelling.
    @Test(
        "Still offers a word said the same way",
        arguments: [
            ("hear", "here"), ("peace", "piece"), ("flower", "flour"), ("aloud", "allowed"),
            ("no", "know"), ("one", "won"), ("by", "buy"), ("buy", "bye"), ("to", "too"),
            ("two", "too"), ("their", "there"), ("there", "they're"), ("your", "you're"),
            ("its", "it's"), ("cite", "site"), ("site", "sight"), ("cache", "cash"),
            ("root", "route"), ("for", "four"), ("ate", "eight"), ("wear", "where"),
            ("weather", "whether"), ("hour", "our"),
        ])
    func offersATrueHomophone(heard: String, homophone: String) {
        #expect(Homophones.share(heard, homophone))
        #expect(!ReadingRestraint.isOrdinaryCollision(homophone, heard: heard))
    }

    /// The defect this list was written for: a sound key files "man" with "main", and neither is a reading of the other.
    @Test(
        "Refuses one ordinary word offered for another that is merely filed with it",
        arguments: [
            ("main", "man"), ("main", "many"), ("mean", "main"), ("man", "many"),
            ("then", "than"), ("affect", "effect"),
        ])
    func refusesAnOrdinaryCollision(heard: String, other: String) {
        #expect(!Homophones.share(heard, other))
        #expect(ReadingRestraint.isOrdinaryCollision(other, heard: heard))
    }

    @Test("Offers nothing at all for a word whose only matches are ordinary collisions")
    func offersNothingForACollision() {
        #expect(GeneralVocabulary.wordsSounding(like: "main").isEmpty)
    }

    @Test("Reads a pair in either order, and a word is no homophone of itself")
    func readsAPairBothWays() {
        #expect(Homophones.share("here", "hear"))
        #expect(Homophones.share("Hear", "HERE"))
        #expect(!Homophones.share("hear", "hear"))
        #expect(Homophones.share("ITS", "it’s"))
    }

    /// Kept by hand and read by every lookup, so it stays a list of pairs and smaller than the vocabulary it guards.
    @Test("Is a list of said-alike sets, each word in one of them, and smaller than the vocabulary")
    func staysASmallHandList() {
        let words = Homophones.groups.flatMap { $0 }

        #expect(Homophones.groups.allSatisfy { $0.count > 1 })
        #expect(Set(words.map(Homophones.lookupKey)).count == words.count)
        #expect(words.allSatisfy { !$0.isEmpty })
        #expect(words.count < 200)
    }
}
