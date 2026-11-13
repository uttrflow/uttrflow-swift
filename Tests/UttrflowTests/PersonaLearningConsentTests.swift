// Tests that a declined application, or the switch in Settings turned off, teaches the persona nothing through the app's own wiring.

import CryptoKit
import Foundation
import Testing
import UttrflowAI
import UttrflowCore
import UttrflowHistory
import UttrflowPipeline
import UttrflowPredict
import UttrflowPredictCapture
import UttrflowSettings
import UttrflowTestSupport

@testable import Uttrflow

private struct Keys: StoreKeyProviding {
    let value = SymmetricKey(size: .bits256)
    func key(createIfMissing: Bool) throws -> SymmetricKey { value }
}

private let declined = "com.example.declined"
private let asked = "com.example.notes"

@MainActor
@Suite("A declined application teaches the persona nothing", .timeLimit(.minutes(1)))
struct PersonaLearningConsentTests {
    /// An app over `root` with `declined` refused, the switch in Settings as `learns` says, and `history` in History.
    private func app(
        in root: URL, learns: Bool, history: [DictationRecord] = [], keeping: (Settings) -> Settings = { $0 }
    ) async throws -> (AppDelegate, EvidenceLedgerStore) {
        try CapturePreferencesFile(
            path: CapturePreferencesFile.defaultFile(in: root).path(percentEncoded: false)
        )
        .save(CapturePreferences(consent: [declined: .declined]))
        let store = UserDefaultsSettingsStore(store: ModelDownloadSettingsStore())
        var settings = store.load()
        settings.learnsFromDictation = learns
        store.save(keeping(settings))
        let keys = EncryptedStore(keys: Keys())
        let past = DictationHistoryStore(
            file: DictationHistoryStore.defaultFile(in: root), encryptedStore: keys)
        for record in history { try await past.append(record, keeping: Retention(days: 30, now: Date())) }
        let app = AppDelegate(
            container: root, clipboardSource: InMemoryClipboardSource(), settingsStore: store,
            account: HeldSession(signedIn: true).layer, encryptedStore: keys)
        app.drawsWindows = false
        return (
            app, EvidenceLedgerStore(file: EvidenceLedgerStore.defaultFile(in: root), encryptedStore: keys)
        )
    }

    private func landed(_ text: String, in bundle: String) -> DictationState {
        .inserted(
            DictationOutcome(
                text: text, method: .accessibility, cleanedBy: .rules, insertedInto: "Notes",
                insertedIntoIdentifier: bundle))
    }

    @Test("a dictation into a declined application writes no style row; one into an unasked application does")
    func declinedApplicationWritesNoRow() async throws {
        let sandbox = Sandbox()
        let (app, ledger) = try await app(in: sandbox.root, learns: true)
        let window = RetentionWindow(days: 365, now: Date())

        app.render(landed("meet me at the usual place", in: declined))
        // The ordinary dictation is the marker that the ledger's writes have run.
        app.render(landed("see you at noon.", in: asked))
        try await eventually { await !ledger.rows(keeping: window).isEmpty }
        await app.learnt.pending?.value

        let rows = await ledger.rows(keeping: window)
        #expect(rows.filter { $0.kind == .styleMessage }.map(\.weight).reduce(0, +) == 1)
        #expect(rows.filter { $0.kind == .styleWords }.map(\.weight).reduce(0, +) == 4)
    }

    @Test("an application History leaves out, or History keeping nothing, teaches the persona nothing")
    func leftOutOfHistoryWritesNoRow() async throws {
        let leftOut = "com.example.records"
        let edit = EvidenceSources.pair(
            kept: EditedSpan(position: 0, old: ["there"], new: ["their"]), day: EvidenceRow.day(of: Date()))
        let window = RetentionWindow(days: 365, now: Date())

        let sandbox = Sandbox()
        let (listed, ledger) = try await app(in: sandbox.root, learns: true) { settings in
            var settings = settings
            settings.historyExcludedApplications = [leftOut.uppercased()]
            return settings
        }
        listed.render(landed("meet me at the usual place", in: leftOut))
        listed.learnt.note(edit, from: leftOut)
        // The ordinary dictation is the marker that the ledger's writes have run.
        listed.render(landed("see you at noon.", in: asked))
        try await eventually { await !ledger.rows(keeping: window).isEmpty }
        await listed.learnt.pending?.value
        let rows = await ledger.rows(keeping: window)
        #expect(rows.filter { $0.kind == .styleMessage }.map(\.weight).reduce(0, +) == 1)
        #expect(rows.filter { $0.kind == .styleWords }.map(\.weight).reduce(0, +) == 4)
        #expect(!rows.contains { row in edit.contains { $0.kind == row.kind } })

        let nothingKept = Sandbox()
        let (quiet, quietLedger) = try await app(in: nothingKept.root, learns: true) { settings in
            var settings = settings
            settings.keepsNoTranscripts = true
            return settings
        }
        quiet.render(landed("see you at noon.", in: asked))
        quiet.learnt.note(edit, from: asked)
        await quiet.learnt.pending?.value
        #expect(await quietLedger.rows(keeping: window).isEmpty)
    }

    @Test("with Learn from my dictation off, a dictation and an edit write no row anywhere")
    func switchedOffWritesNoRow() async throws {
        let sandbox = Sandbox()
        let (app, ledger) = try await app(in: sandbox.root, learns: false)

        app.render(landed("see you at noon.", in: asked))
        app.learnt.note(
            EvidenceSources.pair(
                kept: EditedSpan(position: 0, old: ["there"], new: ["their"]),
                day: EvidenceRow.day(of: Date())),
            from: asked)
        await app.learnt.pending?.value

        #expect(await ledger.rows(keeping: RetentionWindow(days: 365, now: Date())).isEmpty)
    }

    @Test("an edit in a declined application writes no pairing row; one in an unasked application does")
    func declinedEditWritesNoPair() async throws {
        let sandbox = Sandbox()
        let (app, ledger) = try await app(in: sandbox.root, learns: true)
        let rows = EvidenceSources.pair(
            kept: EditedSpan(position: 0, old: ["there"], new: ["their"]), day: EvidenceRow.day(of: Date()))

        app.learnt.note(rows, from: declined)
        await app.learnt.pending?.value
        #expect(await ledger.rows(keeping: RetentionWindow(days: 365, now: Date())).isEmpty)

        app.learnt.note(rows, from: asked)
        await app.learnt.pending?.value
        #expect(await ledger.rows(keeping: RetentionWindow(days: 365, now: Date())).count == rows.count)
    }

    @Test("a dictionary use in a declined application writes no use row, nor any with the switch off")
    func declinedUseWritesNoRow() async throws {
        for learns in [true, false] {
            let sandbox = Sandbox()
            let (app, ledger) = try await app(in: sandbox.root, learns: learns)
            let refused = UUID()
            let counted = UUID()

            await app.noteUses([refused], from: declined)
            await app.noteUses([counted], from: asked)

            let uses = await ledger.rows(keeping: RetentionWindow(days: 365, now: Date())).map(\.subject)
            #expect(uses == (learns ? [counted.uuidString] : []))
        }
    }

    @Test("History's backfill learns nothing from a declined application, nor anything with the switch off")
    func backfillHonoursConsent() async throws {
        let before = Date().addingTimeInterval(-2 * 86_400)
        let history = [
            DictationRecord(
                text: "meet me at the usual place", when: before, applicationName: "Notes",
                applicationIdentifier: declined),
            DictationRecord(
                text: "see you at noon.", when: before, applicationName: "Notes",
                applicationIdentifier: asked),
        ]
        for learns in [true, false] {
            let sandbox = Sandbox()
            let (app, ledger) = try await app(in: sandbox.root, learns: learns, history: history)

            app.sweepExpired()
            await app.sweeping?.value

            let rows = await ledger.rows(keeping: RetentionWindow(days: 365, now: Date()))
            #expect(rows.allSatisfy { $0.provenance == .migration })
            #expect(rows.filter { $0.kind == .styleMessage }.map(\.weight).reduce(0, +) == (learns ? 1 : 0))
            #expect(rows.filter { $0.kind == .styleWords }.map(\.weight).reduce(0, +) == (learns ? 4 : 0))
        }
    }
}
