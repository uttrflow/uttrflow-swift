import Foundation
import Testing
import UttrflowCore
import UttrflowDictionary

@testable import UttrflowAI

@Suite("Plain word list")
struct PersonalWordListTests {
    private let importedAt = Date(timeIntervalSince1970: 1_800_000_000)

    private func emptyStore() -> (PersonalDictionaryStore, URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "uttrflow-word-list-\(UUID().uuidString)")
        return (PersonalDictionaryStore(file: root.appending(path: "dictionary.json")), root)
    }

    @Test("an exported list imports back as the same words and pronunciations, with zero counters")
    func roundTrips() async throws {
        let words = [
            DictionaryEntry(
                word: "Orvanta", pronunciations: ["or vanta", "or wanta"], origin: .added,
                firstSeen: .distantPast, timesUsed: 9, timesReverted: 1),
            DictionaryEntry(word: "kubectl", origin: .added, firstSeen: .distantPast, timesUsed: 4),
            DictionaryEntry(
                word: "Zentrova", pronunciation: "zen trova", origin: .added, firstSeen: .distantPast),
        ]
        let (store, root) = emptyStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let report = try await PersonalDataTransfer.importWordList(
            PersonalWordList.encoded(words), into: store, importedAt: importedAt)

        let kept = await store.allEntries()
        #expect(report.skipped.isEmpty)
        #expect(kept.map(\.word) == words.map(\.word))
        #expect(kept.map(\.pronunciations) == words.map(\.pronunciations))
        #expect(kept.allSatisfy { $0.origin == .added && $0.timesUsed == 0 && $0.timesReverted == 0 })
        #expect(kept.allSatisfy { $0.firstSeen == importedAt })
        #expect(Set(kept.map(\.id)).isDisjoint(with: words.map(\.id)))
    }

    @Test("the export holds only added words and no snippet, identifier, date or counter")
    func exportHoldsOnlyWords() throws {
        let added = DictionaryEntry(
            word: "Orvanta", pronunciation: "or vanta", origin: .added, firstSeen: .distantPast,
            timesUsed: 31_337, timesReverted: 4_242)
        let others = [
            DictionaryEntry(word: "Quellmark", origin: .learned, firstSeen: .distantPast),
            DictionaryEntry(word: "Brintle", origin: .observed, firstSeen: .distantPast),
            DictionaryEntry(word: "Uttrflow", origin: .shipped, firstSeen: .distantPast),
        ]
        let snippet = Snippet(trigger: "my sign off", expansion: "Thanks again", created: .distantPast)

        let text = try #require(String(data: PersonalWordList.encoded([added] + others), encoding: .utf8))

        #expect(text == "Orvanta = or vanta\n")
        for absent in [added.id.uuidString, "31337", "4242", snippet.trigger, snippet.expansion]
            + others.map(\.word)
        {
            #expect(!text.localizedCaseInsensitiveContains(absent), "export holds \(absent)")
        }
    }

    @Test("a file over the line limit is refused with the limit named and nothing written")
    func refusesTooManyLines() async throws {
        let (store, root) = emptyStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let lines = (0..<6_000).map { "Termword\(String($0, radix: 26))" }.joined(separator: "\n")

        await #expect(throws: PersonalWordListError.tooManyLines(maximum: 5_000)) {
            try await PersonalDataTransfer.importWordList(Data(lines.utf8), into: store)
        }
        #expect(await store.allEntries().isEmpty)
    }

    @Test("blank lines count toward neither the limit nor the words, only the numbering")
    func blankLinesOnlyNumber() throws {
        let list = try PersonalWordList(
            decoding: Data("\u{FEFF}Orvanta\r\n\r\n  \n\tZentrova = zen trova  \n".utf8))
        #expect(
            list.lines == [.init(number: 1, text: "Orvanta"), .init(number: 4, text: "Zentrova = zen trova")])
    }

    @Test("twenty bad lines are listed by number and every other line is imported")
    func importsTheRestAndListsBadLines() async throws {
        let (store, root) = emptyStore()
        defer { try? FileManager.default.removeItem(at: root) }
        try await store.add(
            DictionaryEntry(word: "Orvanta", origin: .learned, firstSeen: .distantPast, timesUsed: 7))
        let extras = (0..<9).map { "Termword\(String($0, radix: 26))" }
        let good = ["OpenAI", "Zentrova = zen trova, jen trova", "हाँ"] + extras
        let bad: [(line: String, problem: PersonalWordListReport.Problem)] =
            [
                ("orvanta", .duplicate),
                ("Open AI", .duplicate),
                (String(repeating: "x", count: 65), .tooLong),
                ("Zentrova = " + String(repeating: "zen ", count: 14), .tooLong),
                ("Brin\u{0000}tle", .hiddenCharacter),
                ("Brin\u{202E}tle", .hiddenCharacter),
                ("Москва", .notLatin),
                ("東京", .notLatin),
                ("= or vanta", .refused(.wordIsEmpty)),
                ("Bank of New Zealand", .refused(.entryHasTooManyWords(maximum: 3))),
                ("Quellmark = one two three four", .refused(.entryHasTooManyWords(maximum: 3))),
            ] + extras.map { ($0, .duplicate) }

        let report = try await PersonalDataTransfer.importWordList(
            Data((good + bad.map(\.line)).joined(separator: "\n").utf8), into: store,
            importedAt: importedAt)

        #expect(
            report.skipped
                == bad.enumerated().map {
                    .init(line: good.count + 1 + $0.offset, problem: $0.element.problem)
                })
        #expect(report.added.map(\.word) == ["OpenAI", "Zentrova", "haan"] + extras)
        #expect(report.added[1].pronunciations == ["zen trova", "jen trova"])
        #expect((report.duplicates, report.tooLong, report.refused) == (11, 2, 7))
        let kept = await store.allEntries()
        #expect(kept.first { $0.word == "Orvanta" }?.timesUsed == 7, "an existing word is never overwritten")
        #expect(kept.count == 1 + report.added.count)
    }

    @Test("a selected file above the archive's byte ceiling is refused before decoding")
    func refusesOversizedFile() async throws {
        let (store, root) = emptyStore()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "words.txt")
        try Data(repeating: UInt8(ascii: "a"), count: PersonalDataArchive.maximumSizeInBytes + 1).write(
            to: file)

        await #expect(throws: PersonalDataArchiveError.archiveTooLarge) {
            try await PersonalDataTransfer.importWordList(from: file, into: store)
        }
        #expect(await store.allEntries().isEmpty)
    }

    @Test("malformed bytes and very long lines are refused or reported, never a crash")
    func mutatedListsNeverCrash() throws {
        let valid = Array(
            PersonalWordList.encoded([
                DictionaryEntry(
                    word: "Orvanta", pronunciations: ["or vanta"], origin: .added, firstSeen: .distantPast),
                DictionaryEntry(word: "kubectl", origin: .added, firstSeen: .distantPast),
            ]))
        var random = SeededBytes(seed: 0x11_57)
        for round in 0..<3_000 {
            var bytes = valid
            switch round % 3 {
            case 0:
                for _ in 0...random.next(below: 4) {
                    bytes[random.next(below: bytes.count)] = UInt8(
                        truncatingIfNeeded: random.next(below: 256))
                }
            case 1:
                bytes =
                    Array(bytes.prefix(random.next(below: bytes.count)))
                    + [0xC3, 0x28, 0xF0, 0x9F][random.next(below: 4)...]
            default:
                bytes += Array(
                    repeating: UInt8(ascii: "a") + UInt8(random.next(below: 26)),
                    count: 1 + random.next(below: 10_000))
            }
            do {
                let report = try PersonalWordList(decoding: Data(bytes)).plan(
                    over: [], importedAt: importedAt)
                #expect(report.added.allSatisfy { $0.word.count <= PersonalWordList.maximumLineLength })
            } catch PersonalWordListError.notText {
                continue
            } catch {
                Issue.record("round \(round) failed with an unexpected error: \(error)")
            }
        }
    }
}
