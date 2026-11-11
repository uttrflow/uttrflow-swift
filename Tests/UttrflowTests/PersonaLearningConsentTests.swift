// Tests that a declined application, or the switch in Settings turned off, teaches the persona nothing through the app's own wiring.

import CryptoKit
import Foundation
import Testing
import UttrflowAI
import UttrflowCore
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
    /// An app over `root` with `declined` refused and the switch in Settings as `learns` says.
    private func app(in root: URL, learns: Bool) throws -> (AppDelegate, EvidenceLedgerStore) {
        try CapturePreferencesFile(
            path: CapturePreferencesFile.defaultFile(in: root).path(percentEncoded: false)
        )
        .save(CapturePreferences(consent: [declined: .declined]))
        let store = UserDefaultsSettingsStore(store: ModelDownloadSettingsStore())
        var settings = store.load()
        settings.learnsFromDictation = learns
        store.save(settings)
        let keys = EncryptedStore(keys: Keys())
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
        let (app, ledger) = try app(in: sandbox.root, learns: true)
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

    @Test("with Learn from my dictation off, a dictation and an edit write no row anywhere")
    func switchedOffWritesNoRow() async throws {
        let sandbox = Sandbox()
        let (app, ledger) = try app(in: sandbox.root, learns: false)

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
        let (app, ledger) = try app(in: sandbox.root, learns: true)
        let rows = EvidenceSources.pair(
            kept: EditedSpan(position: 0, old: ["there"], new: ["their"]), day: EvidenceRow.day(of: Date()))

        app.learnt.note(rows, from: declined)
        await app.learnt.pending?.value
        #expect(await ledger.rows(keeping: RetentionWindow(days: 365, now: Date())).isEmpty)

        app.learnt.note(rows, from: asked)
        await app.learnt.pending?.value
        #expect(await ledger.rows(keeping: RetentionWindow(days: 365, now: Date())).count == rows.count)
    }
}
