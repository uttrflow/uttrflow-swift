// Tests for an entry said more than one way.

import Foundation
import Testing

@testable import UttrflowDictionary

@Suite("An entry said several ways")
struct SeveralPronunciationsTests {
    private let noon = Date(timeIntervalSince1970: 1_700_000_000)

    private func zentrova(_ sounds: [String]) -> DictionaryEntry {
        DictionaryEntry(word: "Zentrova", pronunciations: sounds, origin: .added, firstSeen: noon)
    }

    /// A file written before the list holds one `pronunciation` string; it must read back as a list of one.
    @Test("reads a file from before the list as its one pronunciation")
    func oldFileRoundTrips() throws {
        let old = Data(
            #"{"id":"A1B2C3D4-E5F6-4A7B-8C9D-0E1F2A3B4C5D","word":"Zentrova","pronunciation":"zen trova","origin":"added","firstSeen":0,"timesUsed":4,"timesReverted":1}"#
                .utf8)
        let decoded = try JSONDecoder().decode(DictionaryEntry.self, from: old)
        #expect(decoded.pronunciations == ["zen trova"])
        let again = try JSONDecoder().decode(DictionaryEntry.self, from: JSONEncoder().encode(decoded))
        #expect(again == decoded)
    }

    /// The list survives a round trip, and its first entry is still written where an older build reads it.
    @Test("round-trips two pronunciations and keeps the first readable by an older build")
    func listRoundTrips() throws {
        let original = zentrova(["zen trova", "jen trova"])
        let data = try JSONEncoder().encode(original)
        #expect(try JSONDecoder().decode(DictionaryEntry.self, from: data) == original)
        let fields = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(fields["pronunciation"] as? String == "zen trova")
    }

    /// Both ways of saying it and the spelling itself are lookup keys.
    @Test("is found under each pronunciation and under its spelling")
    func foundUnderEveryReading() {
        let entry = zentrova(["zen trova", "jen trova"])
        let index = PhoneticIndex(entries: [entry])
        for heard in ["zen trova", "jen trova", "Zentrova"] {
            #expect(index.candidates(soundingLike: heard).map(\.id) == [entry.id], "\(heard)")
        }
    }

    /// Blanks and repeats add nothing, and the list stops at the stated bound.
    @Test("drops blanks and repeats and stops at the bound")
    func bounded() {
        let many = zentrova(["a", " ", "a", "b", "c", "d", "e", "f"])
        #expect(many.pronunciations == ["a", "b", "c", "d"])
        #expect(many.pronunciations.count == DictionaryEntry.maximumPronunciations)
        #expect(zentrova([]).pronunciation == nil)
    }

    /// Every pronunciation is held to the same word limit as the editor's single field.
    @Test("refuses an entry when any pronunciation is too many words")
    func refusesEachPronunciation() {
        #expect(PhoneticIndex.refusal(for: zentrova(["zen trova"])) == nil)
        #expect(PhoneticIndex.refusal(for: zentrova(["zen trova", "one two three four"])) != nil)
    }
}
