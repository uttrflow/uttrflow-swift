// Tests that a provisional word replaced by hand after a dictation is removed and refused, and nothing else is.

import Foundation
import Testing
import UttrflowAI
import UttrflowContext
import UttrflowDictionary

@testable import Uttrflow
@testable import UttrflowDictionary

@Suite("Edit-away watch")
struct EditAwayWatchTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let field = FocusedFieldIdentity(processIdentifier: 7, elementHash: 11)
    private let inserted = "Ship it to Kubernets tonight."

    /// Answers each read in turn from a fixed list, the last answer repeating.
    private final class FakeReader: Sendable {
        private let answers: [LandedFieldRead?]
        private let count = Counter()
        init(_ answers: [LandedFieldRead?]) { self.answers = answers }
        func read() async -> LandedFieldRead? {
            let index = await count.next()
            return answers[min(index, answers.count - 1)]
        }
    }

    private actor Counter {
        private var value = 0
        func next() -> Int {
            defer { value += 1 }
            return value
        }
    }

    private func store() throws -> (PersonalDictionaryStore, DictionaryEntry, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let dictionary = PersonalDictionaryStore(file: PersonalDictionaryStore.defaultFile(in: root))
        return (dictionary, DictionaryEntry(word: "Kubernets", origin: .learned, firstSeen: now), root)
    }

    private func run(_ answers: [LandedFieldRead?]) async throws -> (kept: [String], refused: [String]) {
        let (dictionary, entry, root) = try store()
        defer { try? FileManager.default.removeItem(at: root) }
        try await dictionary.add(entry)
        #expect(entry.isProvisional)
        let reader = FakeReader(answers)
        let watch = EditAwayWatch(dictionary: dictionary, readField: { await reader.read() }, wait: { _ in })
        await watch.watch([EditAway.Applied(entryID: entry.id, word: entry.word)], inserted: inserted)
        return (await dictionary.allEntries().map(\.word), await dictionary.refusedWords())
    }

    @Test("a provisional word replaced with its neighbours kept is removed and refused")
    func replacedWordIsVetoed() async throws {
        let outcome = try await run([
            LandedFieldRead(field: field, text: inserted),
            LandedFieldRead(field: field, text: "Ship it to Kubernetes tonight."),
        ])
        #expect(outcome.kept.isEmpty)
        #expect(outcome.refused.map { $0.lowercased() } == ["kubernets"])
    }

    @Test("a cleared field vetoes nothing")
    func clearedFieldVetoesNothing() async throws {
        let outcome = try await run([
            LandedFieldRead(field: field, text: inserted), LandedFieldRead(field: field, text: ""),
        ])
        #expect(outcome.kept == ["Kubernets"])
        #expect(outcome.refused.isEmpty)
    }

    @Test("a different field vetoes nothing, even when its text would")
    func differentFieldVetoesNothing() async throws {
        let other = FocusedFieldIdentity(processIdentifier: 7, elementHash: 12)
        let outcome = try await run([
            LandedFieldRead(field: field, text: inserted),
            LandedFieldRead(field: other, text: "Ship it to Kubernetes tonight."),
        ])
        #expect(outcome.kept == ["Kubernets"])
        #expect(outcome.refused.isEmpty)
    }

    @Test("an unreadable field at landing vetoes nothing")
    func unreadableFieldVetoesNothing() async throws {
        let outcome = try await run([
            nil, LandedFieldRead(field: field, text: "Ship it to Kubernetes tonight."),
        ])
        #expect(outcome.kept == ["Kubernets"])
    }

    @Test("the counters hand the watch every used entry, with its standing before this use")
    func countersHandOverProvisionalEntries() async throws {
        actor Seen {
            private(set) var calls: [([EditAway.Applied], String)] = []
            func add(_ applied: [EditAway.Applied], _ text: String) { calls.append((applied, text)) }
        }
        let (dictionary, learned, root) = try store()
        defer { try? FileManager.default.removeItem(at: root) }
        try await dictionary.add(learned)
        let typed = DictionaryEntry(word: "Uttrflow", origin: .added, firstSeen: now)
        try await dictionary.add(typed)
        let seen = Seen()
        let counters = StoreCounters(
            dictionary: dictionary,
            snippets: SnippetStore(file: root.appendingPathComponent("snippets.json")),
            watchEdits: { await seen.add($0, $1) })

        try await counters.recordUse(ofEntries: [], writtenIn: "Uttrflow ships to Kubernets.")

        let calls = await seen.calls
        #expect(
            calls.map(\.0) == [
                [
                    EditAway.Applied(entryID: learned.id, word: "Kubernets"),
                    EditAway.Applied(entryID: typed.id, word: "Uttrflow", isProvisional: false),
                ]
            ])
        #expect(calls.map(\.1) == ["Uttrflow ships to Kubernets."])
    }
}

@Suite("Accepted uses")
struct AcceptedUseTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let field = FocusedFieldIdentity(processIdentifier: 7, elementHash: 11)
    private let inserted = "Ship it to Kubernets tonight."

    private func run(
        _ answers: [LandedFieldRead?], uses: Int = 100
    ) async throws -> DictionaryEntry {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let dictionary = PersonalDictionaryStore(file: PersonalDictionaryStore.defaultFile(in: root))
        let entry = DictionaryEntry(word: "Kubernets", origin: .added, firstSeen: now)
        try await dictionary.add(entry)
        for _ in 0..<uses { try await dictionary.recordUse(of: entry.id) }
        let reads = ReadList(answers)
        let watch = EditAwayWatch(dictionary: dictionary, readField: { await reads.next() }, wait: { _ in })
        await watch.watch(
            [EditAway.Applied(entryID: entry.id, word: entry.word, isProvisional: false)], inserted: inserted)
        return try #require(await dictionary.allEntries().first)
    }

    private actor ReadList {
        private var answers: [LandedFieldRead?]
        init(_ answers: [LandedFieldRead?]) { self.answers = answers }
        func next() -> LandedFieldRead? { answers.count > 1 ? answers.removeFirst() : answers[0] }
    }

    @Test("a word applied a hundred times and never confirmed keeps its rank")
    func unconfirmedUsesRaiseNothing() async throws {
        let entry = try await run([nil], uses: 100)
        #expect(entry.timesUsed == 100)
        #expect(entry.netUses == 0)
    }

    @Test("a word edited away is not accepted")
    func editedWordIsNotAccepted() async throws {
        let entry = try await run(
            [
                LandedFieldRead(field: field, text: inserted),
                LandedFieldRead(field: field, text: "Ship it to Kubernetes tonight."),
            ], uses: 1)
        #expect(entry.netUses == 0)
    }

    @Test("a word left unedited is accepted")
    func unchangedWordIsAccepted() async throws {
        let entry = try await run([LandedFieldRead(field: field, text: inserted)], uses: 1)
        #expect(entry.netUses == 1)
    }

    @Test("a file from before the counter keeps its uses as accepted uses")
    func oldFileKeepsRank() throws {
        let json = """
            {"id":"\(UUID().uuidString)","word":"Foo","origin":"added","firstSeen":0,"timesUsed":5,"timesReverted":1}
            """
        let entry = try JSONDecoder().decode(DictionaryEntry.self, from: Data(json.utf8))
        #expect(entry.timesAccepted == 5)
        #expect(entry.netUses == 4)
    }
}
