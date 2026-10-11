// Tests for spelling preferences projected from evidence rows.

import Foundation
import Testing
import UttrflowCore

@testable import UttrflowDictionary

@Suite("Spelling preferences from edits")
struct SpellingPreferencesTests {
    private func edits(_ old: String, _ new: String, days: [Int]) -> [EvidenceRow] {
        days.flatMap { SpellingPreferences.rows(replacing: [old], with: [new], day: $0) }
    }

    /// Editing "thik" to "theek" on three separate days makes "theek" the preferred spelling.
    @Test("Three confirming days make a preference")
    func threeDaysPrefer() {
        #expect(SpellingPreferences.project(edits("thik", "theek", days: [1, 2, 3])) == ["thik": "theek"])
    }

    /// A lone edit, or three edits on one day, is inert.
    @Test("Fewer than three days teach nothing")
    func loneEditIsInert() {
        #expect(SpellingPreferences.project(edits("thik", "theek", days: [1])).isEmpty)
        #expect(SpellingPreferences.project(edits("thik", "theek", days: [4, 4, 4])).isEmpty)
    }

    /// Two different listed words, or an unlisted word, are never a respelling.
    @Test("A pair that is not two spellings of one word writes no row")
    func nonVariantsRefused() {
        #expect(SpellingPreferences.rows(replacing: ["kab"], with: ["kaam"], day: 1).isEmpty)
        #expect(SpellingPreferences.rows(replacing: ["thick"], with: ["theek"], day: 1).isEmpty)
        #expect(SpellingPreferences.rows(replacing: ["thik"], with: ["thik"], day: 1).isEmpty)
    }

    /// A changed word count is a rewrite, so it writes nothing even when one word is a respelling.
    @Test("A changed word count writes no row")
    func changedCountRefused() {
        #expect(SpellingPreferences.rows(replacing: ["thik"], with: ["theek", "hai"], day: 1).isEmpty)
    }

    /// Only the respelt word of a longer edit is recorded.
    @Test("Only variant pairs of a multi-word edit are recorded")
    func onlyVariantPairs() {
        let rows = SpellingPreferences.rows(replacing: ["thik", "kab"], with: ["theek", "kaam"], day: 1)
        #expect(rows.map(\.subject) == [SpellingPreferences.subject(heard: "thik", meant: "theek")])
    }

    /// Deleting the preference restores the default until three new days confirm it again.
    @Test("Clearing restores the default")
    func clearingRestores() {
        var rows = edits("thik", "theek", days: [1, 2, 3])
        rows += SpellingPreferences.clearing(heard: "thik", meant: "theek", day: 3)
        #expect(SpellingPreferences.project(rows).isEmpty)
        rows += edits("thik", "theek", days: [4, 5])
        #expect(SpellingPreferences.project(rows).isEmpty)
        rows += edits("thik", "theek", days: [6])
        #expect(SpellingPreferences.project(rows) == ["thik": "theek"])
    }

    /// Edits back the other way outweigh the preference rather than leave two spellings preferred.
    @Test("Edits in both directions keep the stronger one")
    func opposingEdits() {
        let rows = edits("thik", "theek", days: [1, 2, 3]) + edits("theek", "thik", days: [4, 5, 6, 7])
        #expect(SpellingPreferences.project(rows) == ["theek": "thik"])
    }
}

@Suite("Spelling preferences in dictated text")
struct PreferredSpellingTests {
    /// A ledger row whose two sides are not spellings of one word never becomes a preference, however often it is seen.
    @Test("A stored pair that is not a variant is refused on projection")
    func nonVariantRowRefused() {
        let rows = [1, 2, 3].map {
            EvidenceRow(
                kind: .spellingPreference, subject: SpellingPreferences.subject(heard: "kab", meant: "kaam"),
                day: $0, provenance: .dictation)
        }
        #expect(SpellingPreferences.project(rows).isEmpty)
    }

    /// Twenty dictations holding the word all use the preferred spelling once three days confirm it; clearing restores the default.
    @Test("The preferred spelling is applied to every dictation and cleared back to the default")
    func appliedAndCleared() {
        var rows = [1, 2, 3].flatMap {
            SpellingPreferences.rows(replacing: ["thik"], with: ["theek"], day: $0)
        }
        let dictations = (0..<20).map {
            $0.isMultiple(of: 2) ? "Thik hai, kal milte hain." : "haan thik hai \($0)"
        }
        let preferred = SpellingPreferences.project(rows)
        let written = dictations.map { PreferredSpelling.applied(to: $0, preferring: preferred) }
        #expect(
            written.filter { $0.lowercased().contains("theek hai") && !$0.lowercased().contains("thik") }
                .count == 20)
        #expect(written.first == "Theek hai, kal milte hain.")
        rows += SpellingPreferences.clearing(heard: "thik", meant: "theek", day: 4)
        let cleared = SpellingPreferences.project(rows)
        #expect(dictations.map { PreferredSpelling.applied(to: $0, preferring: cleared) } == dictations)
    }

    /// A dictionary entry of one listed Hindi word, filed by the user or learnt from an edit.
    private func entry(_ word: String, _ origin: WordOrigin = .added, day: Double = 0) -> DictionaryEntry {
        DictionaryEntry(word: word, origin: origin, firstSeen: Date(timeIntervalSince1970: day * 86_400))
    }

    /// An entry for "theek" writes the confidently heard "thik" its way in 20 of 20 dictations; deleting it restores the default.
    @Test(
        "A dictionary entry's spelling of a listed word is used in every dictation, and deleting it restores it"
    )
    func entrySpellingApplied() {
        let dictations = (0..<20).map {
            $0.isMultiple(of: 2) ? "Thik hai, kal milte hain." : "haan thik hai \($0)"
        }
        let preferred = SpellingPreferences.preferred(filed: [entry("theek")], learnt: [:])
        let written = dictations.map { PreferredSpelling.applied(to: $0, preferring: preferred) }
        #expect(
            written.filter { $0.lowercased().contains("theek hai") && !$0.lowercased().contains("thik") }
                .count == 20)
        let deleted = SpellingPreferences.preferred(filed: [], learnt: [:])
        #expect(dictations.map { PreferredSpelling.applied(to: $0, preferring: deleted) } == dictations)
    }

    /// The entry decides every spelling of its word, so a preference learnt the other way never overrides it.
    @Test("A learnt preference never overrides a dictionary entry")
    func entryOutranksLearnt() {
        let learnt = ["thik": "theek", "nahi": "nahin"]
        let preferred = SpellingPreferences.preferred(filed: [entry("thik")], learnt: learnt)
        #expect(preferred["thik"] == nil)
        #expect(preferred["theek"] == "thik")
        #expect(preferred["nahi"] == "nahin")
        #expect(PreferredSpelling.applied(to: "theek hai", preferring: preferred) == "thik hai")
    }

    /// Of two entries spelling one word, the one the user typed wins over one learnt, and the newer of two alike.
    @Test("An entry the user typed outranks a learnt one, and a newer entry an older one")
    func typedEntryOutranksLearntEntry() {
        let typed = SpellingPreferences.preferred(
            filed: [entry("theek", .learned, day: 9), entry("thik", .added, day: 1)], learnt: [:])
        #expect(typed["theek"] == "thik" && typed["thik"] == nil)
        let newer = SpellingPreferences.preferred(
            filed: [entry("thik", .learned, day: 1), entry("theek", .learned, day: 9)], learnt: [:])
        #expect(newer["thik"] == "theek" && newer["theek"] == nil)
    }

    /// A word that is no listed Hindi word, or a spelling that is also English, is never respelt by an entry.
    @Test("Only listed Hindi spellings that are not English are respelt by an entry")
    func entryLeavesOtherWordsAlone() {
        #expect(
            SpellingPreferences.preferred(filed: [entry("Kubernetes"), entry("kaam")], learnt: [:]).isEmpty)
        let preferred = SpellingPreferences.preferred(filed: [entry("mein"), entry("theek")], learnt: [:])
        #expect(preferred["main"] == nil)
        #expect(
            PreferredSpelling.applied(to: "the main thick branch", preferring: preferred)
                == "the main thick branch")
    }

    /// Only whole words change: a word containing the heard spelling, and English text, stay as written.
    @Test("Only whole words are respelt")
    func wholeWordsOnly() {
        let preferred = ["thik": "theek"]
        #expect(
            PreferredSpelling.applied(to: "thikness is thik.", preferring: preferred) == "thikness is theek.")
        #expect(
            PreferredSpelling.applied(to: "Ship the build today.", preferring: preferred)
                == "Ship the build today.")
    }
}
