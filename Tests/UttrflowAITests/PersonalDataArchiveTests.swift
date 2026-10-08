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

    private let importedAt = Date(timeIntervalSince1970: 1_000_000)

    @Test("export and import preserves both lists, the words reset to new additions")
    func roundTrip() throws {
        let archive = PersonalDataArchive(dictionary: [word], snippets: [snippet])
        let decoded = try PersonalDataArchive.decode(archive.encoded())
        #expect(decoded == archive)
        let words = decoded.mergedDictionary(into: [], importedAt: importedAt)
        let snippets = decoded.mergedSnippets(into: [])
        #expect(
            words.records == [
                DictionaryEntry(
                    id: word.id, word: "Uttrflow", pronunciation: "utter flow", origin: .added,
                    firstSeen: importedAt)
            ])
        #expect(snippets.records == [snippet])
        #expect(words.duplicates == 0)
        #expect(snippets.duplicates == 0)
    }

    @Test("export and import keep a caret marker and an escaped marker exactly as stored")
    func roundTripsMarkers() throws {
        let marked = Snippet(
            id: UUID(), trigger: "reply", expansion: "Hi {caret},\nwrite \\{caret} literally",
            created: Date(timeIntervalSince1970: 3))
        let archive = PersonalDataArchive(dictionary: [], snippets: [marked])
        let decoded = try PersonalDataArchive.decode(archive.encoded())
        #expect(decoded.mergedSnippets(into: []).records == [marked])
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

        let words = incoming.mergedDictionary(into: [existingWord], importedAt: .distantPast)
        let snippets = incoming.mergedSnippets(into: [existingSnippet])
        #expect(words.records == [existingWord, extraWord])
        #expect(snippets.records == [existingSnippet, extraSnippet])
        #expect(words.duplicates == 1)
        #expect(snippets.duplicates == 1)
    }

    @Test("every pronunciation travels through export and import")
    func everyPronunciationRoundTrips() throws {
        let said = DictionaryEntry(
            word: "Zentrova", pronunciations: ["zen trova", "jen trova"], origin: .added,
            firstSeen: .distantPast)
        let decoded = try PersonalDataArchive.decode(
            PersonalDataArchive(dictionary: [said], snippets: []).encoded())
        let words = decoded.mergedDictionary(into: [], importedAt: importedAt)
        #expect(words.records.map(\.pronunciations) == [["zen trova", "jen trova"]])
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

    @Test("a mutated archive's origin, counters and dates are not imported")
    func resetsRankingState() throws {
        let forged = [Date.distantPast, Date.distantFuture].enumerated().map { index, date in
            DictionaryEntry(
                word: "forged\(index)", origin: .shipped, firstSeen: date,
                timesUsed: Int.max, timesReverted: Int.max)
        }
        let decoded = try PersonalDataArchive.decode(
            PersonalDataArchive(dictionary: forged, snippets: []).encoded())
        let words = decoded.mergedDictionary(into: [], importedAt: importedAt).records
        #expect(words.map(\.word) == ["forged0", "forged1"])
        #expect(words.allSatisfy { $0.origin == .added && $0.firstSeen == importedAt })
        #expect(words.allSatisfy { $0.timesUsed == 0 && $0.timesReverted == 0 })
    }

    @Test("an archived shipped word leaves the seeded record and its counters in place")
    func keepsSeededShippedWord() {
        let seeded = DictionaryEntry(
            word: "Uttrflow", origin: .shipped, firstSeen: .distantPast)
        let archived = DictionaryEntry(
            id: UUID(), word: "Uttrflow", origin: .shipped,
            firstSeen: Date(timeIntervalSince1970: 5), timesUsed: 8, timesReverted: 2)
        let merged = PersonalDataArchive(dictionary: [archived], snippets: [])
            .mergedDictionary(into: [seeded], importedAt: importedAt)
        #expect(merged.records == [seeded])
        #expect(merged.duplicates == 1)
    }

    @Test("an archive over the dictionary word count is refused")
    func refusesTooManyWords() throws {
        let words = (0..<5_000).map {
            DictionaryEntry(word: "word\($0)", origin: .added, firstSeen: .distantPast)
        }
        let bytes = try JSONEncoder().encode(PersonalDataArchive(dictionary: words, snippets: []))
        #expect(throws: PersonalDataArchiveError.tooManyDictionaryEntries) {
            try PersonalDataArchive.decode(bytes)
        }
        let atLimit = Array(words.prefix(PersonalDataArchive.maximumDictionaryEntryCount))
        let accepted = try PersonalDataArchive.decode(
            JSONEncoder().encode(PersonalDataArchive(dictionary: atLimit, snippets: [])))
        #expect(accepted.dictionary.count == PersonalDataArchive.maximumDictionaryEntryCount)
    }

    @Test("an imported record whose identifier is already held under another word or trigger gets its own")
    func rekeysCollidingIdentifiers() {
        let renamedWord = DictionaryEntry(
            id: word.id, word: "Uttrflowing", origin: .added, firstSeen: .distantPast)
        let renamedSnippet = Snippet(
            id: snippet.id, trigger: "home address", expansion: "42 Example Road", created: .distantPast)
        let incoming = PersonalDataArchive(dictionary: [renamedWord], snippets: [renamedSnippet])

        let words = incoming.mergedDictionary(into: [word], importedAt: importedAt).records
        let snippets = incoming.mergedSnippets(into: [snippet]).records
        #expect(words.map(\.word) == ["Uttrflow", "Uttrflowing"])
        #expect(Set(words.map(\.id)).count == 2)
        #expect(snippets.map(\.trigger) == ["my address", "home address"])
        #expect(Set(snippets.map(\.id)).count == 2)
    }

    @Test("a spelling or trigger holding a control or bidirectional character is refused")
    func refusesHiddenCharacters() throws {
        for hidden in ["\u{0007}", "\u{202E}", "\u{2066}", "\u{200F}"] {
            let word = DictionaryEntry(word: "exam\(hidden)ple", origin: .added, firstSeen: .distantPast)
            let snippet = Snippet(trigger: "my\(hidden) note", expansion: "Saved text", created: .distantPast)
            for archive in [
                PersonalDataArchive(dictionary: [word], snippets: []),
                PersonalDataArchive(dictionary: [], snippets: [snippet]),
            ] {
                let bytes = try JSONEncoder().encode(archive)
                #expect(throws: PersonalDataArchiveError.hiddenCharacters) {
                    try PersonalDataArchive.decode(bytes)
                }
            }
        }
        let lines = Snippet(trigger: "sign off", expansion: "Thanks,\n\tSam", created: .distantPast)
        let bytes = try JSONEncoder().encode(PersonalDataArchive(dictionary: [], snippets: [lines]))
        #expect(try PersonalDataArchive.decode(bytes).snippets.count == 1)
    }

    @Test("ten thousand mutated archives are each refused or decoded valid, never a crash")
    func mutatedArchivesNeverCrash() throws {
        let valid = try PersonalDataArchive(dictionary: [word], snippets: [snippet]).encoded()
        var random = SeededBytes(seed: 0x5EED)
        for round in 0..<10_000 {
            let mutated = Self.mutate(valid, round: round, random: &random)
            do {
                let archive = try PersonalDataArchive.decode(mutated)
                #expect(throws: Never.self) { try archive.encoded() }
            } catch is PersonalDataArchiveError, is DecodingError {
                continue
            } catch {
                Issue.record("round \(round) failed with an unexpected error: \(error)")
            }
        }
    }

    /// One mutation of a valid archive, chosen by the round so every kind is covered.
    private static func mutate(_ data: Data, round: Int, random: inout SeededBytes) -> Data {
        var bytes = [UInt8](data)
        switch round % 6 {
        case 0:
            return Data(bytes.prefix(random.next(below: bytes.count)))
        case 1:
            for _ in 0...random.next(below: 4) {
                bytes[random.next(below: bytes.count)] = UInt8(truncatingIfNeeded: random.next(below: 256))
            }
            return Data(bytes)
        case 2:
            let depth = 1 + random.next(below: 4_000)
            return Data((String(repeating: "[", count: depth) + String(repeating: "]", count: depth)).utf8)
        case 3:
            let text = String(decoding: bytes, as: UTF8.self)
            return Data(text.replacingOccurrences(of: "{\"", with: "{\"version\":1,\"").utf8)
        case 4:
            let text = String(decoding: bytes, as: UTF8.self)
            return Data(text.replacingOccurrences(of: "\"version\":1", with: "\"version\":\"1\"").utf8)
        default:
            let text = String(decoding: bytes, as: UTF8.self)
            let huge = ["1e400", "-99999999999999999999999", "18446744073709551616"][random.next(below: 3)]
            return Data(text.replacingOccurrences(of: "\"timesUsed\":3", with: "\"timesUsed\":\(huge)").utf8)
        }
    }
}

/// A small seeded generator, so a failing mutation is reproduced by its round; the word-list fuzz case shares it.
struct SeededBytes {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    /// A value in `0..<bound`, or 0 when the bound is 0.
    mutating func next(below bound: Int) -> Int {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        mixed ^= mixed >> 31
        return bound > 0 ? Int(mixed % UInt64(bound)) : 0
    }
}
