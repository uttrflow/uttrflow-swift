import Foundation
import Testing
import UttrflowCore
import UttrflowDictionary

@testable import UttrflowAI

@Suite("Personal data archive")
struct PersonalDataArchiveTests {
    private let word = DictionaryEntry(
        id: UUID(),
        word: "Uttrflow", pronunciation: "utter flow", origin: .added,
        firstSeen: Date(timeIntervalSince1970: 1), timesUsed: 3, timesReverted: 1)
    private let snippet = Snippet(
        id: UUID(),
        trigger: "my address", expansion: "42 Example Road", created: Date(timeIntervalSince1970: 2))

    @Test("export and import preserves both lists and their metadata")
    func roundTrip() throws {
        let archive = PersonalDataArchive(dictionary: [word], snippets: [snippet])
        let decoded = try PersonalDataArchive.decode(archive.encoded())
        #expect(decoded == archive)
        let merged = decoded.merging(dictionary: [], snippets: [])
        #expect(merged.dictionary == [word])
        #expect(merged.snippets == [snippet])
        #expect(merged.duplicateWords == 0)
        #expect(merged.duplicateSnippets == 0)
    }

    @Test("import merges records and reports case-insensitive word and trigger duplicates")
    func mergeAndReportDuplicates() {
        let existingWord = DictionaryEntry(
            word: "uttrflow", origin: .added, firstSeen: Date(timeIntervalSince1970: 3))
        let existingSnippet = Snippet(
            trigger: "MY address", expansion: "Existing", created: Date(timeIntervalSince1970: 4))
        let extraWord = DictionaryEntry(word: "Kubernetes", origin: .added, firstSeen: .distantPast)
        let extraSnippet = Snippet(trigger: "my email", expansion: "a@example.com", created: .distantPast)
        let incoming = PersonalDataArchive(
            dictionary: [word, extraWord], snippets: [snippet, extraSnippet])

        let merged = incoming.merging(
            dictionary: [existingWord], snippets: [existingSnippet])
        #expect(merged.dictionary == [existingWord, extraWord])
        #expect(merged.snippets == [existingSnippet, extraSnippet])
        #expect(merged.duplicateWords == 1)
        #expect(merged.duplicateSnippets == 1)
    }

    @Test("unsupported versions, malformed JSON and invalid records are refused")
    func refusesInvalidArchive() throws {
        let unsupported = try JSONEncoder().encode(
            PersonalDataArchive(dictionary: [], snippets: [], version: 99))
        #expect(throws: PersonalDataArchiveError.self) {
            try PersonalDataArchive.decode(unsupported)
        }
        #expect(throws: (any Error).self) {
            try PersonalDataArchive.decode(Data("{not-json".utf8))
        }
        let invalid = PersonalDataArchive(
            dictionary: [],
            snippets: [Snippet(trigger: "!!!", expansion: "", created: .distantPast)])
        #expect(throws: PersonalDataArchiveError.self) { try invalid.encoded() }
    }

    @Test("rejects a raw archive over the byte limit before JSON decoding")
    func refusesOversizedArchive() {
        let data = Data(repeating: 0x20, count: PersonalDataArchive.maximumSizeInBytes + 1)
        #expect(throws: PersonalDataArchiveError.self) { try PersonalDataArchive.decode(data) }
    }

    @Test("caps imported snippet count and string lengths")
    func refusesExcessiveSnippetData() throws {
        let tooMany = (0...PersonalDataArchive.maximumSnippetCount).map { index in
            Snippet(trigger: "phrase \(index)", expansion: "Saved text", created: .distantPast)
        }
        let countBytes = try JSONEncoder().encode(PersonalDataArchive(dictionary: [], snippets: tooMany))
        #expect(throws: PersonalDataArchiveError.self) { try PersonalDataArchive.decode(countBytes) }

        let longSnippet = Snippet(
            trigger: "phrase",
            expansion: String(repeating: "x", count: PersonalDataArchive.maximumSnippetExpansionBytes + 1),
            created: .distantPast)
        let snippetBytes = try JSONEncoder().encode(
            PersonalDataArchive(dictionary: [], snippets: [longSnippet]))
        #expect(throws: PersonalDataArchiveError.self) { try PersonalDataArchive.decode(snippetBytes) }

        let longWord = DictionaryEntry(
            word: String(repeating: "x", count: PersonalDataArchive.maximumDictionaryWordBytes + 1),
            origin: .added, firstSeen: .distantPast)
        let wordBytes = try JSONEncoder().encode(PersonalDataArchive(dictionary: [longWord], snippets: []))
        #expect(throws: PersonalDataArchiveError.self) { try PersonalDataArchive.decode(wordBytes) }
    }

    @Test("replaces a freshly seeded shipped word with its archived identity")
    func restoresShippedWordIdentity() {
        let seeded = DictionaryEntry(
            word: "Uttrflow", origin: .shipped, firstSeen: .distantPast)
        let archived = DictionaryEntry(
            id: UUID(), word: "Uttrflow", origin: .shipped,
            firstSeen: Date(timeIntervalSince1970: 5), timesUsed: 8, timesReverted: 2)
        let merged = PersonalDataArchive(dictionary: [archived], snippets: [])
            .merging(dictionary: [seeded], snippets: [])
        #expect(merged.dictionary == [archived])
        #expect(merged.duplicateWords == 1)
    }
}
