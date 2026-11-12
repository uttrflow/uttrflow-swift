// Tests the rows the app writes to the evidence ledger from dictation, undo and History.

import CryptoKit
import Foundation
import os
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

    @Test("History never backfills a dictation made in a private-browsing window")
    func privateRecordIsNotBackfilled() {
        let entry = DictionaryEntry(word: "Kubernetes", origin: .added, firstSeen: now)
        let record = DictationRecord(
            text: "Deploy it on Kubernetes.", when: now.addingTimeInterval(-3 * 86_400),
            applicationName: "Browser", applicationIdentifier: "com.example.browser",
            fromPrivateWindow: true)
        #expect(EvidenceSources.backfill([record], entries: [entry], ledger: [], overrides: .none).isEmpty)
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
            ledger, from: records, consent: NothingAskedYet(), dictionary: dictionary,
            overrides: .none, keeping: window)
        let first = await ledger.rows(keeping: window)
        await EvidenceSources.backfill(
            ledger, from: records, consent: NothingAskedYet(), dictionary: dictionary,
            overrides: .none, keeping: window)

        #expect(first.contains { $0.kind == .use && $0.provenance == .migration })
        #expect(await ledger.rows(keeping: window) == first)
        await EvidenceSources.backfill(
            nil, from: records, consent: NothingAskedYet(), dictionary: dictionary,
            overrides: .none, keeping: window)
    }

    @Test("an unreadable ledger is kept aside, rebuilt from History by the sweep, and named")
    func unreadableLedgerIsRebuiltFromHistory() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let encrypted = EncryptedStore(keys: Keys())
        let file = EvidenceLedgerStore.defaultFile(in: root)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encrypted.seal(Data("not a ledger".utf8), for: file.lastPathComponent).write(to: file)
        let ledger = EvidenceLedgerStore(file: file, encryptedStore: encrypted)
        let dictionary = PersonalDictionaryStore(file: PersonalDictionaryStore.defaultFile(in: root))
        try await dictionary.add(word: "Kubernetes", pronunciation: "", at: now)
        let records = [
            DictationRecord(text: "Deploy it on Kubernetes.", when: now.addingTimeInterval(-86_400))
        ]
        let window = RetentionWindow(days: RetentionWindow.keepAlwaysDays, now: now)

        await EvidenceSources.backfill(
            ledger, from: records, consent: NothingAskedYet(), dictionary: dictionary,
            overrides: .none, keeping: window)

        let rebuilt = await ledger.rows(keeping: window)
        #expect(rebuilt.contains { $0.kind == .use && $0.provenance == .migration })
        #expect(await ledger.refusal() == .setAside)
    }

    /// One answer `Revocable` gave, in the order it gave them.
    private struct Answer: Sendable {
        let application: String?
        let state: ConsentState
    }

    /// Consent the person can withdraw at any moment, logging every answer in the order given.
    private final class Revocable: LearningConsent, Sendable {
        private let held = OSAllocatedUnfairLock(initialState: (withdrawn: false, answers: [Answer]()))
        var answers: [Answer] { held.withLock { $0.answers } }
        func withdraw() { held.withLock { $0.withdrawn = true } }
        func state(of bundleIdentifier: String?) -> ConsentState {
            held.withLock {
                let state: ConsentState = $0.withdrawn ? .declined : .allowed
                $0.answers.append(Answer(application: bundleIdentifier, state: state))
                return state
            }
        }
    }

    @Test("consent withdrawn after a learner's own check and before the ledger writes authorises no row")
    func withdrawnBeforeTheWriteWritesNothing() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let ledger = EvidenceLedgerStore(
            file: EvidenceLedgerStore.defaultFile(in: root), encryptedStore: EncryptedStore(keys: Keys()))
        let window = RetentionWindow(days: RetentionWindow.keepAlwaysDays, now: now)
        let consent = Revocable()
        let application = "com.example.notes"
        let rows = [EvidenceRow(kind: .styleMessage, subject: "plain", day: today, provenance: .dictation)]

        #expect(consent.mayLearn(from: application))
        consent.withdraw()
        try await ledger.append(rows, keeping: window, learntIn: application, consent: consent)
        #expect(await ledger.rows(keeping: window).isEmpty)

        try await ledger.append(rows, keeping: window, learntIn: application, consent: Revocable())
        #expect(await ledger.rows(keeping: window) == rows)
    }

    @Test(
        "a withdrawal raced against 100 writes lets no row land once a write has seen it",
        arguments: 0..<20)
    func racedWithdrawalWritesNothingAfter(round: Int) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let ledger = EvidenceLedgerStore(
            file: EvidenceLedgerStore.defaultFile(in: root), encryptedStore: EncryptedStore(keys: Keys()))
        let window = RetentionWindow(days: RetentionWindow.keepAlwaysDays, now: now)
        let consent = Revocable()
        let day = today

        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<100 {
                if index == 50 { group.addTask { consent.withdraw() } }
                group.addTask {
                    let row = EvidenceRow(
                        kind: .styleMessage, subject: "\(index)", day: day, provenance: .dictation)
                    try await ledger.append([row], keeping: window, learntIn: "\(index)", consent: consent)
                }
            }
            try await group.waitForAll()
        }

        let answers = consent.answers
        let firstRefusal = answers.firstIndex { $0.state == .declined } ?? answers.endIndex
        #expect(answers[firstRefusal...].allSatisfy { $0.state == .declined })
        // Rows land in the order their answers were given, so none was written after a refusal was seen.
        let allowed = answers[..<firstRefusal].map { $0.application ?? "" }
        #expect(await ledger.rows(keeping: window).map(\.subject) == allowed)
    }

    @Test("a sweep with nothing to backfill still deletes ledger rows past History's window")
    func sweepWithNothingLearnableExpiresRows() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let ledger = EvidenceLedgerStore(
            file: EvidenceLedgerStore.defaultFile(in: root), encryptedStore: EncryptedStore(keys: Keys()))
        let dictionary = PersonalDictionaryStore(file: PersonalDictionaryStore.defaultFile(in: root))
        let always = RetentionWindow(days: RetentionWindow.keepAlwaysDays, now: now)
        try await ledger.append(
            [EvidenceRow(kind: .styleMessage, subject: "plain", day: today - 60, provenance: .dictation)],
            keeping: always)

        await EvidenceSources.backfill(
            ledger, from: [], consent: NothingAskedYet(), dictionary: dictionary, overrides: .none,
            keeping: RetentionWindow(days: 30, now: now))

        #expect(await ledger.rows(keeping: always).isEmpty)
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
        ) { used, _ in await noted.add(used) }

        try await counters.recordUse(ofEntries: [], writtenIn: "nothing known here", in: nil)
        try await counters.recordUse(ofEntries: [], writtenIn: "Deploy it on Kubernetes.", in: nil)
        try await counters.recordUse(ofSnippets: [])

        #expect(await noted.ids == [[entry.id]])
    }

    @Test("a re-dictation of a private-window dictation writes no retry row, either way round")
    func privateRecordIsNotPairedOnRetry() {
        let correction = RecordedCorrection(
            heard: "nickel", wrote: "Nikhil", wordRange: 1..<2, entryID: UUID(),
            reason: .saidClearlyElsewhere, heardConfidence: 0.3)
        let first = { (isPrivate: Bool) in
            DictationRecord(
                text: "Ask Nikhil about the meeting.", when: self.now,
                applicationIdentifier: "com.example.notes",
                changes: RecordedChanges(corrections: [correction]), arrival: .confirmed,
                heard: "ask nickel about the meeting", fromPrivateWindow: isPrivate)
        }
        let retry = { (isPrivate: Bool) in
            DictationRecord(
                text: "Ask Nikhel about the meeting.", when: self.now.addingTimeInterval(5),
                applicationIdentifier: "com.example.notes", arrival: .confirmed,
                heard: "ask Nikhel about the meeting", fromPrivateWindow: isPrivate)
        }
        #expect(!EvidenceSources.retried(first(false), by: retry(false)).isEmpty)
        #expect(EvidenceSources.retried(first(true), by: retry(false)).isEmpty)
        #expect(EvidenceSources.retried(first(false), by: retry(true)).isEmpty)
    }

    @Test(
        "a re-dictation in the same app within the respeak window writes a retry row for a dropped correction"
    )
    func reDictationRetriesItsPairing() {
        let correction = RecordedCorrection(
            heard: "nickel", wrote: "Nikhil", wordRange: 1..<2, entryID: UUID(),
            reason: .saidClearlyElsewhere, heardConfidence: 0.3)
        let first = DictationRecord(
            text: "Ask Nikhil about the meeting.", when: now, applicationIdentifier: "com.example.notes",
            changes: RecordedChanges(corrections: [correction]), arrival: .confirmed,
            heard: "ask nickel about the meeting")
        let retry = { (seconds: Double, app: String) in
            DictationRecord(
                text: "Ask Nikhel about the meeting.", when: self.now.addingTimeInterval(seconds),
                applicationIdentifier: app, arrival: .confirmed, heard: "ask Nikhel about the meeting")
        }
        let key = ConfusionPairs.key(heard: "nickel", meant: "Nikhil")
        #expect(
            EvidenceSources.retried(first, by: retry(5, "com.example.notes")) == [
                EvidenceRow(kind: .pairRetried, subject: key, day: today, provenance: .dictation)
            ])
        #expect(EvidenceSources.retried(first, by: retry(31, "com.example.notes")).isEmpty)
        #expect(EvidenceSources.retried(first, by: retry(5, "com.example.mail")).isEmpty)
    }
}
