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

    private func entry(_ origin: WordOrigin, used: Int, reverted: Int) -> DictionaryEntry {
        DictionaryEntry(
            word: "Uttrflow", origin: origin, firstSeen: noon, timesUsed: used, timesReverted: reverted)
    }

    /// The rule before the bound, kept to compare against: half the uses undone, once there are three.
    private func halfRule(used: Int, reverted: Int) -> Bool {
        used >= 3 && Double(reverted) / Double(used) >= 0.5
    }

    /// The use count at which a word whose undos arrive at `rate` retires, or nil within `limit` uses.
    private func retirementUse(
        rate: Double, limit: Int = 300, rule: (Int, Int) -> Bool
    ) -> Int? {
        for used in 1...limit {
            let reverted = Int((rate * Double(used)).rounded(.down))
            if rule(used, reverted) { return used }
        }
        return nil
    }

    /// A word wrong 30% of the time was kept for ever by the half rule.
    @Test("a learned word undone well above the allowed rate retires before half its uses are undone")
    func learnedRetiresBelowHalf() {
        #expect(entry(.learned, used: 20, reverted: 9).isTrustworthy == false)
        #expect(entry(.observed, used: 20, reverted: 9).isTrustworthy == false)
        #expect(entry(.learned, used: 30, reverted: 12).isTrustworthy == false)
        #expect(entry(.learned, used: 30, reverted: 9).isTrustworthy)
        #expect(entry(.learned, used: 10, reverted: 2).isTrustworthy)
    }

    /// Undos by a person who typed the word in can be about something else.
    @Test("a word the person typed in is not retired by a few undos")
    func addedWordNeedsMuchMoreEvidence() {
        #expect(entry(.added, used: 2, reverted: 2).isTrustworthy)
        #expect(entry(.added, used: 4, reverted: 3).isTrustworthy)
        #expect(entry(.added, used: 9, reverted: 9).isTrustworthy)
        #expect(entry(.added, used: 10, reverted: 10).isTrustworthy == false)
        #expect(entry(.added, used: 30, reverted: 24).isTrustworthy == false)
        #expect(entry(.added, used: 30, reverted: 10).isTrustworthy)
    }

    @Test("a shipped word follows the same rule as a typed one")
    func shippedWordNeedsMuchMoreEvidence() {
        #expect(entry(.shipped, used: 4, reverted: 3).isTrustworthy)
        #expect(entry(.shipped, used: 10, reverted: 10).isTrustworthy == false)
    }

    /// A retired word is hidden from correction, not deleted; the counters are all that changes.
    @Test("retirement only reads the counters, so restoring clears it")
    func retirementReadsCounters() {
        var retired = entry(.learned, used: 6, reverted: 4)
        #expect(retired.isTrustworthy == false)
        retired.timesReverted = 0
        #expect(retired.isTrustworthy)
    }

    /// The simulation the design asks for: each revert-rate profile against today's rule.
    @Test("retires wrong words at 40% and 60% undone and keeps 5% and 20% for ever")
    func simulatedRevertRateProfiles() throws {
        for origin in [WordOrigin.learned, .observed] {
            let rule: (Int, Int) -> Bool = {
                !DictionaryEntry.isTrustworthy(origin: origin, used: $0, reverted: $1)
            }
            #expect(retirementUse(rate: 0.05, rule: rule) == nil)
            #expect(retirementUse(rate: 0.20, rule: rule) == nil)
            let at40 = retirementUse(rate: 0.40, rule: rule)
            let at60 = retirementUse(rate: 0.60, rule: rule)
            #expect(at40 != nil)
            #expect(retirementUse(rate: 0.40, rule: halfRule) == nil)
            #expect(try #require(at60) <= 10)
        }
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
