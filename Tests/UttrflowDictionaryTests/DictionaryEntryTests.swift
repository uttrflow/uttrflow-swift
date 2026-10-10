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

    @Test("spelling identity preserves symbols that distinguish technical terms")
    func spellingKeyPreservesMeaningfulSymbols() {
        let distinctSpellings = ["C++", "C#", "C", ".NET", "NET", "R&D", "RD", "Node.js", "Nodejs"]
        let keys = distinctSpellings.map(DictionaryEntry.spellingKey(for:))

        #expect(Set(keys).count == distinctSpellings.count)
        #expect(DictionaryEntry.spellingKey(for: "Open AI") == DictionaryEntry.spellingKey(for: "OpenAI"))
        #expect(DictionaryEntry.spellingKey(for: "C++") == "c++")
        #expect(DictionaryEntry.spellingKey(for: "C#") == "c#")
        #expect(DictionaryEntry.spellingKey(for: ".NET") == ".net")
    }

    /// A hand-edited file can carry a counter no normal path ever produces; the initializer refuses it too.
    @Test("clamps a counter built outside the domain, not just one decoded outside it")
    func initializerClampsOutOfDomainCounters() {
        let entry = entry(used: .max, reverted: .min)
        #expect(entry.timesUsed == DictionaryEntry.maximumCount)
        #expect(entry.timesReverted == 0)
    }

    /// A structurally valid but hand-edited entry must decode into the domain ranking and undo assume.
    @Test("decodes an extreme counter into the domain rather than carrying it through")
    func decodingClampsOutOfDomainCounters() throws {
        let data = try rawDictionaryEntryJSON(
            id: UUID(), word: "Wrong", pronunciation: nil, origin: .added, firstSeen: noon,
            timesUsed: .max, timesReverted: .min)
        let decoded = try JSONDecoder().decode(DictionaryEntry.self, from: data)
        #expect(decoded.timesUsed == DictionaryEntry.maximumCount)
        #expect(decoded.timesReverted == 0)
        // Everything else about the entry survives the recovery untouched.
        #expect(decoded.word == "Wrong")
        #expect(decoded.origin == .added)
    }

    /// The whole point of the domain: this combination would overflow `Int` before the clamp existed.
    @Test("netUses never overflows, even at the extremes of the domain")
    func netUsesNeverOverflows() {
        #expect(entry(used: 0, reverted: .max).netUses == -DictionaryEntry.maximumCount)
        #expect(entry(used: .max, reverted: 0).netUses == DictionaryEntry.maximumCount)
    }
}
