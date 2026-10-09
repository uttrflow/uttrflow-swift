// Tests the rows the app writes to the evidence ledger from dictation, undo and History.

import CryptoKit
import Foundation
import Testing
import UttrflowAI
import UttrflowCore
import UttrflowDictionary
import UttrflowHistory
import UttrflowPredictCapture

@testable import Uttrflow

@Suite("Evidence sources")
struct EvidenceSourcesTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var today: Int { EvidenceRow.day(of: now) }

    @Test("a used entry writes a use row and an undone correction a revert row, carrying no text")
    func liveRows() {
        let id = UUID()
        #expect(
            EvidenceSources.uses(of: [id], day: today) == [
                EvidenceRow(kind: .use, subject: id.uuidString, day: today, provenance: .dictation)
            ])
        #expect(
            EvidenceSources.revert(of: id, day: today)
                == EvidenceRow(kind: .revert, subject: id.uuidString, day: today, provenance: .undo))
    }

    @Test(
        "History backfills dictionary uses and style counts once, and never a day the ledger already covers")
    func backfill() {
        let entry = DictionaryEntry(word: "Kubernetes", origin: .added, firstSeen: now)
        let old = DictationRecord(
            text: "Deploy it on Kubernetes.", when: now.addingTimeInterval(-3 * 86_400),
            applicationName: "Notes", applicationIdentifier: "com.example.notes")
        let recent = DictationRecord(text: "Kubernetes again", when: now)
        let rows = EvidenceSources.backfill([recent, old], entries: [entry], ledger: [], overrides: .none)
        #expect(rows.allSatisfy { $0.provenance == .migration })
        #expect(rows.filter { $0.kind == .use }.map(\.subject) == [entry.id.uuidString, entry.id.uuidString])
        #expect(rows.filter { $0.kind == .styleMessage }.count == 2)
        #expect(!rows.contains { $0.subject.contains("Deploy") })

        let live = [EvidenceRow(kind: .styleMessage, subject: "plain", day: today, provenance: .dictation)]
        let older = EvidenceSources.backfill([recent, old], entries: [entry], ledger: live, overrides: .none)
        #expect(Set(older.map(\.day)) == [today - 3])
        #expect(EvidenceSources.backfill([old], entries: [entry], ledger: rows, overrides: .none).isEmpty)
    }

    private struct Keys: StoreKeyProviding {
        let value = SymmetricKey(size: .bits256)
        func key(createIfMissing: Bool) throws -> SymmetricKey { value }
    }

    @Test("the sweep writes History's backfill into the ledger once, however often it runs")
    func backfillsTheLedgerOnce() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let ledger = EvidenceLedgerStore(
            file: EvidenceLedgerStore.defaultFile(in: root), encryptedStore: EncryptedStore(keys: Keys()))
        let dictionary = PersonalDictionaryStore(file: PersonalDictionaryStore.defaultFile(in: root))
        try await dictionary.add(word: "Kubernetes", pronunciation: "", at: now)
        let records = [
            DictationRecord(text: "Deploy it on Kubernetes.", when: now.addingTimeInterval(-86_400))
        ]
        let window = RetentionWindow(days: RetentionWindow.keepAlwaysDays, now: now)

        await EvidenceSources.backfill(
            ledger, from: records, dictionary: dictionary, overrides: .none, keeping: window)
        let first = await ledger.rows(keeping: window)
        await EvidenceSources.backfill(
            ledger, from: records, dictionary: dictionary, overrides: .none, keeping: window)

        #expect(first.contains { $0.kind == .use && $0.provenance == .migration })
        #expect(await ledger.rows(keeping: window) == first)
        await EvidenceSources.backfill(
            nil, from: records, dictionary: dictionary, overrides: .none, keeping: window)
    }

    @Test("one undo through History vetoes that heard-to-meant pairing only, and blames its entry")
    func undoVetoesItsPairing() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let history = DictationHistoryStore(file: DictationHistoryStore.defaultFile(in: root))
        let retention = Retention(days: 30, now: .now)
        let entry = UUID()
        let correction = RecordedCorrection(
            heard: "nickel", wrote: "Nikhil", wordRange: 2..<3, entryID: entry,
            reason: .saidClearlyElsewhere, heardConfidence: 0.3)
        try await history.append(
            DictationRecord(
                text: "ask the Nikhil", when: .now,
                changes: RecordedChanges(corrections: [correction], snippets: [])),
            keeping: retention)

        let reverted = try #require(try await history.undoCorrection(correction.id, keeping: retention))
        let rows =
            EvidenceSources.undone(reverted, day: today)
            + ConfusionPairs.confirming(heard: "pickle", meant: "Nikhil", day: today)

        #expect(rows.first == EvidenceSources.revert(of: entry, day: today))
        #expect(
            ConfusionPairs.project(rows) == [ConfusionPairs.key(heard: "nickel", meant: "Nikhil"): .vetoed])
    }

    @Test("an edit replacing inserted words confirms that pairing on its day; additions and long runs do not")
    func keptEditConfirms() {
        let key = ConfusionPairs.key(heard: "nickel", meant: "Nikhil")
        let edit = EditedSpan(position: 2, old: ["nickel,"], new: ["Nikhil,"])
        #expect(EvidenceSources.pair(kept: edit, day: today).map(\.subject) == [key])
        let threeDays = (1...3).flatMap { EvidenceSources.pair(kept: edit, day: today + $0) }
        #expect(ConfusionPairs.project(threeDays) == [key: .confirmed])
        #expect(ConfusionPairs.project(Array(threeDays.prefix(2))).isEmpty)
        #expect(
            EvidenceSources.pair(kept: EditedSpan(position: 0, old: [], new: ["Nikhil"]), day: today).isEmpty)
        #expect(
            EvidenceSources.pair(kept: EditedSpan(position: 0, old: ["nickel"], new: []), day: today).isEmpty)
        let long = EditedSpan(position: 0, old: ["a", "b", "c", "d"], new: ["Nikhil"])
        #expect(EvidenceSources.pair(kept: long, day: today).isEmpty)
    }

    @Test(
        "a landed dictation tells the ledger exactly the entries the dictionary counted, and nothing when none"
    )
    func countersNoteTheUsedEntries() async throws {
        actor Noted {
            private(set) var ids: [[UUID]] = []
            func add(_ new: [UUID]) { ids.append(new) }
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let dictionary = PersonalDictionaryStore(file: PersonalDictionaryStore.defaultFile(in: root))
        let entry = try #require(
            try await dictionary.add(word: "Kubernetes", pronunciation: "", at: now).first)
        let noted = Noted()
        let counters = StoreCounters(
            dictionary: dictionary, snippets: SnippetStore(file: root.appendingPathComponent("snippets.json"))
        ) { await noted.add($0) }

        try await counters.recordUse(ofEntries: [], writtenIn: "nothing known here")
        try await counters.recordUse(ofEntries: [], writtenIn: "Deploy it on Kubernetes.")
        try await counters.recordUse(ofSnippets: [])

        #expect(await noted.ids == [[entry.id]])
    }
}
