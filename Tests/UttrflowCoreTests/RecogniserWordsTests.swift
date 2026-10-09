// Tests for the recogniser-word table, the one definition of an ordinary word.

import Testing

@testable import UttrflowCore

@Suite("The words the recogniser spells as one token")
struct RecogniserWordsTests {
    @Test("the shipped table loads from the bundle with every derived word")
    func loadsFromTheBundle() {
        #expect(RecogniserWords.table.source == .bundled)
        #expect(RecogniserWords.all.count == 20_477)
    }

    /// The tokenizer spells a weekday as one token only capitalised, so the lowercase table does not hold it.
    @Test("holds lowercase one-token words and nothing the tokenizer splits")
    func holdsOneTokenWords() {
        #expect(RecogniserWords.all.isSuperset(of: ["the", "cache", "cash", "mint", "select", "merge"]))
        #expect(RecogniserWords.all.isDisjoint(with: ["monday", "rebase", "webhook", "nahi", "The"]))
    }

    /// Rows are in merge order, so a word the recogniser's training text holds more often ranks first.
    @Test("ranks a common spelling ahead of a rare one said the same way")
    func ranksByFrequency() throws {
        #expect(RecogniserWords.rank(of: "the") == 6)
        for (common, rare) in [("the", "thee"), ("apple", "appel"), ("made", "maid"), ("sale", "sail")] {
            let first = try #require(RecogniserWords.rank(of: common))
            let second = try #require(RecogniserWords.rank(of: rare))
            #expect(first < second)
        }
        #expect(RecogniserWords.rank(of: "rebase") == nil)
        #expect(RecogniserWords.rank(of: "The") == nil)
    }
}
