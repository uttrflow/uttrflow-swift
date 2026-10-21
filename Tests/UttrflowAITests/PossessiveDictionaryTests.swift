import Foundation
import Testing
import UttrflowDictionary

@testable import UttrflowAI

/// A dictionary spelling keeps the possessive the speaker added, even when the apostrophe makes no sound.
@Suite("Possessive dictionary spellings", .bug(id: 7989))
struct PossessiveDictionaryTests {
    private static func index(_ words: String...) -> PhoneticIndex {
        PhoneticIndex(
            entries: words.map {
                DictionaryEntry(word: $0, origin: .added, firstSeen: Date(timeIntervalSince1970: 0))
            })
    }

    @Test(
        "a possessive of an entry is spelled with the entry and its own ending",
        arguments: [
            ("Kubernetes", "kubernetes's", "Kubernetes's"), ("Redis", "redis's", "Redis's"),
            ("Postgres", "postgres's", "Postgres's"),
            ("Kubernetes", "kubernetes\u{2019}s", "Kubernetes\u{2019}s"),
        ])
    func keepsThePossessive(entry: String, heard: String, written: String) {
        let words = WordCorrectionEngine.spellings(of: heard, in: Self.index(entry)).map(\.word)
        #expect(words.contains(written), "\(heard) → \(words)")
        #expect(!words.contains(entry), "\(heard) was offered the bare \(entry): \(words)")
    }

    @Test("a bare plural ending is still read whole first, since an entry may end in s")
    func bareSKeepsTheWholeReading() {
        let words = WordCorrectionEngine.spellings(of: "redis", in: Self.index("Redis")).map(\.word)
        #expect(words == ["Redis"])
    }

    @Test("a possessive already written is left alone")
    func writtenPossessiveStays() {
        #expect(WordCorrectionEngine.spellings(of: "Kubernetes's", in: Self.index("Kubernetes")).isEmpty)
    }
}
