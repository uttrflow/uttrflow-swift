// Tests for the pronouncing dictionary, its weighted distance and its one-edit index.

import Testing

@testable import UttrflowCore

@Suite("The phoneme lexicon finds exactly the words within weighted distance 1, through its index")
struct PhonemeLexiconTests {
    private static let listing = """
        ;;; a comment line has no phonemes after the head
        hear HH IY1 R
        here HH IY1 R
        hair HH EH1 R
        beer B IY1 R
        peer P IY1 R
        pier P IY1 R
        appear AH0 P IH1 R
        tomato T AH0 M EY1 T OW2
        tomato(2) T AH0 M AA1 T OW2
        potato P AH0 T EY1 T OW2
        cat K AE1 T
        dog D AO1 G
        broken q1 X
        stressed AH12 X
        bud B AH1 D # comment after the listing
        """

    private let lexicon = PhonemeLexicon(listing: Self.listing)

    @Test("Listings are read in order, alternatives merged, unknown phonemes and comments skipped")
    func readsTheListing() {
        #expect(lexicon.words.first == "hear")
        #expect(!lexicon.words.contains("broken") && !lexicon.words.contains("stressed"))
        #expect(lexicon.sounds(of: "Tomato").count == 2)
        #expect(lexicon.sounds(of: "bud").count == 1)
        #expect(lexicon.sounds(of: "unknown").isEmpty)
        #expect(lexicon.holds("HEAR") && !lexicon.holds("unknown"))
    }

    @Test("A vowel for a vowel and a voicing pair cost half; other edits cost one")
    func weighsEdits() throws {
        #expect(lexicon.distance("hear", "here") == 0)
        #expect(lexicon.distance("hear", "hair") == 0.5)
        #expect(lexicon.distance("beer", "peer") == 0.5)
        #expect(lexicon.distance("hear", "beer") == 1)
        #expect(lexicon.distance("cat", "dog") == 2.5)
        #expect(lexicon.distance("tomato", "potato") == 2)
        #expect(lexicon.distance("hear", "absent") == nil)
    }

    @Test("Neighbours are every word within distance 1, nearest first, never the word itself")
    func findsNeighbours() {
        #expect(lexicon.words(of: "hear") == ["here", "hair", "beer", "peer", "pier"])
        #expect(lexicon.words(within: 0, of: "HEAR") == ["here"])
        #expect(lexicon.words(within: 5, of: "peer") == ["pier", "beer", "hear", "here"])
        #expect(lexicon.words(of: "absent").isEmpty)
    }

    @Test("Without classes every substitution costs one")
    func classesComeFromTheirText() {
        let plain = PhonemeLexicon(listing: Self.listing, classes: "")
        #expect(plain.distance("hear", "hair") == 1)
        #expect(plain.words(within: 0.5, of: "beer").isEmpty)
    }

    @Test("The index misses nothing brute force finds within distance 1")
    func indexIsComplete() {
        for word in lexicon.words {
            let brute = lexicon.words.filter { $0 != word && (lexicon.distance(word, $0) ?? 9) <= 1 }
            #expect(Set(lexicon.words(of: word)) == Set(brute), "\(word)")
        }
    }

    @Test("The bundled lexicon loads and holds the homophones the hand list was kept for")
    func bundledLexiconLoads() throws {
        let bundled = try #require(PhonemeLexicon.bundled)
        #expect(bundled.words.count > 30_000)
        #expect(bundled.words(within: 0, of: "their").contains("there"))
        #expect(bundled.distance("affect", "effect") == 0)
    }
}
