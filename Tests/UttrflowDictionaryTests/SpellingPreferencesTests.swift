// Tests for spelling preferences projected from evidence rows.

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
