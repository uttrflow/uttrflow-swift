import Foundation
import Testing
import UttrflowCore
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

    @Test(
        "a surely heard possessive of an entry is written in the entry's case with its ending kept",
        .bug(id: 8111),
        arguments: [
            ("Kubernetes", "we checked kubernetes's status", "Kubernetes's"),
            ("Grafana", "open grafana's settings.", "Grafana's"),
            ("Kubernetes", "the kubernetes\u{2019}s logs", "Kubernetes\u{2019}s"),
        ])
    func recasesThePossessive(entry: String, said: String, written: String) {
        let heard = said.split(separator: " ").map { SpokenWord(text: String($0), confidence: 0.95) }
        let recased = WordCorrectionEngine.recasings(
            of: Utterance(words: heard), against: Self.index(entry))
        #expect(recased.map { WordShape($0.replacement).core } == [written], "\(said) → \(recased)")
    }

    @Test("a possessive written in the entry's case, or a plural, is not recased", .bug(id: 8111))
    func leavesAWrittenPossessiveAndAPluralAlone() {
        let heard = ["Kubernetes's", "kuberneteses"].map { SpokenWord(text: $0, confidence: 0.95) }
        let recased = WordCorrectionEngine.recasings(
            of: Utterance(words: heard), against: Self.index("Kubernetes"))
        #expect(recased.isEmpty, "\(recased)")
    }
}
