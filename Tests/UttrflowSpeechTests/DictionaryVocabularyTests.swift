// Tests the dictionary-backed vocabulary source.
import Foundation
import Testing

@testable import UttrflowCore
import UttrflowDictionary
@testable import UttrflowSpeech

@Suite("DictionaryVocabulary")
struct DictionaryVocabularyTests {
    private static let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func entry(_ word: String, daysOld: Double = 0, timesUsed: Int = 0) -> DictionaryEntry {
        DictionaryEntry(
            word: word,
            origin: .added,
            firstSeen: Self.now.addingTimeInterval(-daysOld * 86_400),
            timesUsed: timesUsed
        )
    }

    private func source(
        limit: Int = WorkingSet.defaultLimit,
        entries: [DictionaryEntry],
        context: AppContext = .unknown
    ) -> DictionaryVocabulary {
        DictionaryVocabulary(limit: limit) { (entries, context, Self.now) }
    }

    @Test("offers the dictionary ranked, best first")
    func ranksByValue() async {
        let words = await source(
            entries: [entry("Seldom", daysOld: 300), entry("Often", timesUsed: 40)]
        ).vocabulary()

        #expect(words == ["Often", "Seldom"])
    }

    @Test("favours what the frontmost app is showing")
    func favoursScreen() async {
        let words = await source(
            entries: [entry("Often", timesUsed: 40), entry("PaymentSheet")],
            context: AppContext(documentName: "PaymentSheet.swift")
        ).vocabulary()

        #expect(words.first == "PaymentSheet")
    }

    @Test("stops at the limit it was given")
    func honoursLimit() async {
        let words = await source(
            limit: 2, entries: (0..<10).map { entry("word\($0)") }
        ).vocabulary()

        #expect(words.count == 2)
    }

    @Test("an empty dictionary asks for no biasing at all")
    func emptyDictionary() async {
        #expect(await source(entries: []).vocabulary().isEmpty)
    }
}
