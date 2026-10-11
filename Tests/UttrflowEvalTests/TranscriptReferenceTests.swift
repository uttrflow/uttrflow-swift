// Tests that a transcript-only category's references are the spoken words with some taken away, never rewritten.
import Testing
import UttrflowCore

@testable import UttrflowEval

/// Holds every reference in a transcript-only category to the filter rule, so a reference cannot reward a rewrite.
@Suite("Transcript references")
struct TranscriptReferenceTests {
    /// Whether `expected` is the spoken words in order with some removed, each written word one or more spoken ones.
    private static func keepsOnlySpokenWords(_ testCase: EvaluationCase) -> Bool {
        let spoken = Scorer.spellingFolded(Scorer.tokens(testCase.spoken), in: testCase)
        let written = numeralsJoined(Scorer.spellingFolded(Scorer.tokens(testCase.expected), in: testCase))
        // The earliest spoken position the written words so far can end at; skipping a spoken word removes it.
        var reached = 0
        for word in written {
            guard let end = earliestEnd(of: word, in: spoken, from: reached) else { return false }
            reached = end
        }
        return true
    }

    /// Where the first spoken run from `start` whose letters are `word` ends; a numeral may write any number words.
    private static func earliestEnd(of word: String, in spoken: [String], from start: Int) -> Int? {
        if word.contains(where: \.isNumber) { return start < spoken.count ? start + 1 : nil }
        for first in start..<spoken.count {
            var letters = ""
            var end = first
            while end < spoken.count, letters.count < word.count {
                letters += spoken[end]
                end += 1
            }
            if letters == word { return end }
        }
        return nil
    }

    /// Adjacent numeral pieces as one numeral, so "2,000,000,000" and "2:30" each write one spoken number.
    private static func numeralsJoined(_ words: [String]) -> [String] {
        words.reduce(into: []) { joined, word in
            if word.contains(where: \.isNumber), let last = joined.last, last.contains(where: \.isNumber) {
                joined[joined.count - 1] = last + word
            } else {
                joined.append(word)
            }
        }
    }

    private func reference(_ spoken: String, _ expected: String) -> EvaluationCase {
        EvaluationCase(id: "probe", category: .everyday, spoken: spoken, expected: expected)
    }

    @Test func everyTranscriptOnlyReferenceIsTheSpokenWordsWithSomeRemoved() {
        // A Devanagari utterance is romanised, a change of script with no shared letters to compare.
        let held = EvaluationCorpus.all.filter {
            $0.category.isTranscriptOnly && !Romaniser.containsDevanagari($0.spoken)
        }
        #expect(held.count > 300)
        let rewritten = held.filter { !Self.keepsOnlySpokenWords($0) }.map(\.id)
        #expect(rewritten.isEmpty, "references that rewrite what was said: \(rewritten)")
    }

    @Test func removalNumeralsAndClosedSpacesKeepAReference() {
        #expect(Self.keepsOnlySpokenWords(reference("um the the build passed period", "The build passed.")))
        #expect(Self.keepsOnlySpokenWords(reference("open package dot json", "Open package.json.")))
        #expect(Self.keepsOnlySpokenWords(reference("about fifteen people came", "About 15 people came.")))
        #expect(Self.keepsOnlySpokenWords(reference("we raised two billion", "We raised 2,000,000,000.")))
        #expect(Self.keepsOnlySpokenWords(reference("open a p r for it", "Open a PR for it.")))
    }

    @Test func aRepairedReorderedOrAddedWordIsARewrite() {
        #expect(!Self.keepsOnlySpokenWords(reference("we have went home", "We have gone home.")))
        #expect(!Self.keepsOnlySpokenWords(reference("ship it today", "Today, ship it.")))
        #expect(
            !Self.keepsOnlySpokenWords(
                reference("it slipped we found a bug", "It slipped as we found a bug.")))
    }
}
