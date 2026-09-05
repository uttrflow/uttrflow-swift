// Tests for one dictionary entry.

import Foundation
import Testing

@testable import UttrflowDictionary

@Suite("What one dictionary entry is")
struct DictionaryEntryTests {
    private let noon = Date(timeIntervalSince1970: 1_700_000_000)

    private func entry(used: Int, reverted: Int) -> DictionaryEntry {
        DictionaryEntry(
            word: "Uttrflow", origin: .learned, firstSeen: noon,
            timesUsed: used, timesReverted: reverted)
    }

    /// The index keys on sound, so a name spelt nothing like it is said offers the pronunciation.
    @Test("is indexed by how it sounds, not how it is written")
    func indexedBySound() {
        #expect(DictionaryEntry(word: "Nikhil", origin: .added, firstSeen: noon).soundsLike == "Nikhil")
        #expect(
            DictionaryEntry(word: "Nikhil", pronunciation: "Nikeel", origin: .added, firstSeen: noon)
                .soundsLike == "Nikeel")
    }

    /// An entry the user keeps undoing is teaching the app to be wrong, and the evidence is already counted.
    @Test("retires itself once it is undone more often than not")
    func retiresWhenReverted() {
        #expect(entry(used: 10, reverted: 8).isTrustworthy == false)
        #expect(entry(used: 10, reverted: 1).isTrustworthy)
    }

    /// A single bad day must not retire a good word.
    @Test("is trusted until there is enough evidence to doubt it")
    func trustedWhileYoung() {
        #expect(entry(used: 1, reverted: 1).isTrustworthy)
        #expect(entry(used: 2, reverted: 2).isTrustworthy)
        #expect(entry(used: 3, reverted: 3).isTrustworthy == false)
    }

    @Test("round-trips through Codable with every field")
    func codable() throws {
        let original = DictionaryEntry(
            word: "Claude", pronunciation: "Clawed", origin: .observed, firstSeen: noon,
            timesUsed: 4, timesReverted: 1)
        let decoded = try JSONDecoder().decode(
            DictionaryEntry.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
    }
}
