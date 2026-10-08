import Foundation
import Testing
import UttrflowCore
import UttrflowDictionary

@testable import UttrflowAI

@Suite("Personal data import")
struct PersonalDataTransferTests {
    @Test("refuses an oversized selected file before reading or writing stores")
    func oversizedSelectedFileDoesNotWrite() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "uttrflow-personal-data-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let archiveURL = root.appending(path: "archive.json")
        try Data(count: PersonalDataArchive.maximumSizeInBytes + 1).write(to: archiveURL)
        let dictionary = PersonalDictionaryStore(file: root.appending(path: "dictionary.json"))
        let snippets = SnippetStore(file: root.appending(path: "snippets.json"))

        do {
            _ = try await PersonalDataTransfer.importArchive(
                from: archiveURL, into: dictionary, and: snippets)
            Issue.record("oversized archive was accepted")
        } catch PersonalDataArchiveError.archiveTooLarge {
            #expect(await dictionary.allEntries().isEmpty)
            #expect(await snippets.snippets().isEmpty)
        } catch {
            Issue.record("unexpected import error: \(error)")
        }
    }

    @Test("refuses a malformed archive before changing either store")
    func malformedArchiveDoesNotWrite() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "uttrflow-personal-data-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let dictionary = PersonalDictionaryStore(file: root.appending(path: "dictionary.json"))
        let snippets = SnippetStore(file: root.appending(path: "snippets.json"))
        try await dictionary.add(
            DictionaryEntry(word: "Uttrflow", origin: .added, firstSeen: .distantPast))
        try await snippets.save(
            Snippet(trigger: "my address", expansion: "42 Example Road", created: .distantPast))
        let wordsBefore = await dictionary.allEntries()
        let snippetsBefore = await snippets.snippets()

        do {
            _ = try await PersonalDataTransfer.importArchive(
                Data("not a personal-data archive".utf8), into: dictionary, and: snippets)
            Issue.record("malformed archive was accepted")
        } catch {}

        #expect(await dictionary.allEntries() == wordsBefore)
        #expect(await snippets.snippets() == snippetsBefore)
    }

    @Test("valid imports merge once and return duplicate counts")
    func importsAndReportsDuplicates() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "uttrflow-personal-data-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let dictionary = PersonalDictionaryStore(file: root.appending(path: "dictionary.json"))
        let snippets = SnippetStore(file: root.appending(path: "snippets.json"))
        let knownWord = DictionaryEntry(word: "Uttrflow", origin: .added, firstSeen: .distantPast)
        let newWord = DictionaryEntry(word: "Kubernetes", origin: .added, firstSeen: .distantPast)
        let knownSnippet = Snippet(
            trigger: "my address", expansion: "Existing", created: .distantPast)
        let newSnippet = Snippet(
            trigger: "my email", expansion: "a@example.com", created: .distantPast)
        try await dictionary.add(knownWord)
        try await snippets.save(knownSnippet)
        let bytes = try PersonalDataArchive(
            dictionary: [
                DictionaryEntry(word: "uttrflow", origin: .learned, firstSeen: .distantPast), newWord,
            ],
            snippets: [
                Snippet(trigger: "MY address", expansion: "Imported", created: .distantPast), newSnippet,
            ]
        ).encoded()

        let result = try await PersonalDataTransfer.importArchive(
            bytes, into: dictionary, and: snippets, importedAt: .distantPast)
        #expect(result.duplicateWords == 1)
        #expect(result.duplicateSnippets == 1)
        #expect(await dictionary.allEntries() == [knownWord, newWord])
        #expect(await snippets.snippets() == [knownSnippet, newSnippet])
    }

    @Test("a snippet whose trigger says a spoken command is imported but counted, since the command wins")
    func flagsSnippetsThatSayCommands() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "uttrflow-personal-data-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let dictionary = PersonalDictionaryStore(file: root.appending(path: "dictionary.json"))
        let snippets = SnippetStore(file: root.appending(path: "snippets.json"))
        let colliding = Snippet(trigger: "new line", expansion: "Kind regards", created: .distantPast)
        let ordinary = Snippet(trigger: "my email", expansion: "a@example.com", created: .distantPast)
        let bytes = try PersonalDataArchive(dictionary: [], snippets: [colliding, ordinary]).encoded()

        let result = try await PersonalDataTransfer.importArchive(
            bytes, into: dictionary, and: snippets, importedAt: .distantPast)

        #expect(result.snippetsSayingCommands == 1)
        #expect(await snippets.snippets().map(\.trigger) == ["new line", "my email"])
        #expect(!(await snippets.expander()).expand("first new line second").didExpand)
    }

    @Test("imported words arrive as additions, so they never displace the local inferred words")
    func mergesOverLimitKeepingStrongest() async throws {
        func run() async throws -> (PersonalDataImportReport, [DictionaryEntry], [Snippet]) {
            let root = URL(fileURLWithPath: NSTemporaryDirectory())
                .appending(path: "uttrflow-personal-data-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: root) }
            let dictionary = PersonalDictionaryStore(file: root.appending(path: "dictionary.json"))
            let snippets = SnippetStore(file: root.appending(path: "snippets.json"))
            let local = (0..<200).map {
                DictionaryEntry(
                    word: "local\($0)", origin: .learned,
                    firstSeen: Date(timeIntervalSince1970: Double($0)), timesUsed: $0 % 7)
            }
            try await dictionary.replaceAll { _ in (local, ()) }
            try await snippets.save(
                Snippet(trigger: "my address", expansion: "1 Example Road", created: .distantPast))
            let imported =
                (0..<200).map {
                    DictionaryEntry(
                        word: "remote\($0)", origin: .observed,
                        firstSeen: Date(timeIntervalSince1970: Double($0)), timesUsed: $0 % 5)
                } + [DictionaryEntry(word: "Kubernetes", origin: .added, firstSeen: .distantPast)]
            let archive = try PersonalDataArchive(
                dictionary: imported,
                snippets: [Snippet(trigger: "my email", expansion: "a@example.com", created: .distantPast)]
            ).encoded()
            let report = try await PersonalDataTransfer.importArchive(
                archive, into: dictionary, and: snippets)
            return (report, await dictionary.allEntries(), await snippets.snippets())
        }

        let (report, words, kept) = try await run()
        let inferred = words.filter { $0.origin == .learned || $0.origin == .observed }
        #expect(inferred.map(\.word) == (0..<200).map { "local\($0)" })
        #expect(report.skippedInferredWords == 0)
        #expect(words.filter { $0.origin == .added }.count == 201)
        #expect(Set(kept.map(\.expansion)) == ["1 Example Road", "a@example.com"])
        let (_, again, _) = try await run()
        #expect(again.map(\.word) == words.map(\.word))
    }

    @Test("a dictionary that cannot be written leaves the snippets as they were")
    func failedSecondWriteUndoesTheFirst() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "uttrflow-personal-data-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let blocker = root.appending(path: "blocker")
        try Data().write(to: blocker)
        let dictionary = PersonalDictionaryStore(file: blocker.appending(path: "dictionary.json"))
        let snippets = SnippetStore(file: root.appending(path: "snippets.json"))
        try await snippets.save(
            Snippet(trigger: "my address", expansion: "1 Example Road", created: .distantPast))
        let before = await snippets.snippets()
        let archive = try PersonalDataArchive(
            dictionary: [DictionaryEntry(word: "Kubernetes", origin: .added, firstSeen: .distantPast)],
            snippets: [Snippet(trigger: "my email", expansion: "a@example.com", created: .distantPast)]
        ).encoded()

        await #expect(throws: DictionaryStoreError.self) {
            try await PersonalDataTransfer.importArchive(archive, into: dictionary, and: snippets)
        }
        #expect(await snippets.snippets() == before)
    }
}
