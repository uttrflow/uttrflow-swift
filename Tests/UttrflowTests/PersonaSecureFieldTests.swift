// Tests that a secure field or a credential-shaped dictation teaches the persona nothing, through the app's own learning wiring.

import CryptoKit
import Foundation
import Synchronization
import Testing
import UttrflowAI
import UttrflowCore
import UttrflowDictionary
import UttrflowPipeline
import UttrflowTestSupport

@testable import Uttrflow

/// Proposes one scripted correction, so a dictation applies a real dictionary entry.
private struct OneCorrection: WordCorrecting {
    let correction: DictationCorrection

    func corrections(
        for transcription: Transcription, seeing context: AppContext
    ) async throws(DictationChangeError) -> [DictationCorrection] {
        [correction]
    }
}

/// Fires one snippet, as the snippet store's expander would for its trigger.
private struct OneSnippet: SnippetExpanding {
    let id: UUID

    func expand(_ text: String) async throws(DictationChangeError) -> ExpandedTranscript {
        ExpandedTranscript(
            text: text.replacing("my sign off", with: "Thanks again"),
            snippets: [SnippetUse(snippetID: id, matched: "my sign off", expansion: "Thanks again")])
    }
}

private struct Keys: StoreKeyProviding {
    let value = SymmetricKey(size: .bits256)
    func key(createIfMissing: Bool) throws -> SymmetricKey { value }
}

private let spoken = "open the payment sheet and add my sign off"

@Suite("A secure field teaches the persona nothing", .timeLimit(.minutes(1)))
struct PersonaSecureFieldTests {
    /// Runs one dictation through the real counters, dictionary and snippet stores, and returns what the ledger was told.
    private func dictate(
        into context: AppContext, in root: URL
    ) async throws -> (ledgerUses: [UUID], entry: DictionaryEntry?, snippet: Snippet?) {
        let dictionary = PersonalDictionaryStore(file: PersonalDictionaryStore.defaultFile(in: root))
        let snippets = SnippetStore(file: SnippetStore.defaultFile(in: root))
        let entry = DictionaryEntry(word: "PaymentSheet", origin: .added, firstSeen: .now)
        _ = try await dictionary.add(entry)
        let snippet = Snippet(trigger: "my sign off", expansion: "Thanks again", created: .now)
        _ = try await snippets.save(snippet)
        let told = Mutex<[UUID]>([])
        let pipeline = DictationPipeline(
            capture: FakeAudioCaptureEngine(),
            speech: FakeSpeechEngine(transcribeOutcome: .success(.fixture(text: spoken))),
            cleaner: FakeTranscriptCleaner(producedBy: .rules),
            context: FakeContextEngine(context: context),
            inserter: FakeTextInserter(),
            corrector: OneCorrection(
                correction: DictationCorrection(
                    heard: "payment sheet", wrote: "PaymentSheet", wordRange: 2..<4, entryID: entry.id,
                    reason: .heardAsSeveralWords, heardConfidence: 0.2)),
            snippets: OneSnippet(id: snippet.id),
            learner: StoreCounters(
                dictionary: dictionary, snippets: snippets,
                noteUses: { used in told.withLock { $0 += used } }),
            clock: ManualClock())

        await pipeline.startRecording()
        await pipeline.finishRecording()
        guard case .inserted = await pipeline.currentState else {
            Issue.record("expected an insertion, got \(await pipeline.currentState)")
            return ([], nil, nil)
        }
        return (
            told.withLock { $0 }, await dictionary.allEntries().first { $0.id == entry.id },
            await snippets.snippets().first { $0.id == snippet.id }
        )
    }

    @Test("a dictionary word and a snippet used in a secure field are counted nowhere")
    func secureFieldCountsNothing() async throws {
        let sandbox = Sandbox()
        let result = try await dictate(into: .fixture(isSecure: true), in: sandbox.root)

        #expect(result.ledgerUses.isEmpty)
        #expect(result.entry?.timesUsed == 0)
        #expect(result.snippet?.timesUsed == 0)
        #expect(result.snippet?.lastUsed == nil)
    }

    @Test("the same dictation into an ordinary field is counted, so the secure case is not vacuous")
    func ordinaryFieldCounts() async throws {
        let sandbox = Sandbox()
        let result = try await dictate(into: .fixture(), in: sandbox.root)

        #expect(result.ledgerUses.count == 1)
        #expect(result.entry?.timesUsed == 1)
        #expect(result.snippet?.timesUsed == 1)
    }

    @MainActor
    @Test("a secure or credential-shaped dictation that landed writes no row to the evidence ledger")
    func landedSecretWritesNoRow() async throws {
        let sandbox = Sandbox()
        let keys = EncryptedStore(keys: Keys())
        let app = AppDelegate(
            container: sandbox.root, account: HeldSession(signedIn: true).layer, encryptedStore: keys)
        app.drawsWindows = false
        let ledger = EvidenceLedgerStore(
            file: EvidenceLedgerStore.defaultFile(in: sandbox.root), encryptedStore: keys)
        let window = RetentionWindow(days: 365, now: Date())

        app.render(
            .inserted(
                DictationOutcome(
                    text: "meet me at the usual place", method: .accessibility, cleanedBy: .rules,
                    insertedInto: "Notes", intoSecureField: true)))
        app.render(
            .inserted(
                DictationOutcome(
                    text: "the access key id is ASIAY34FZKBOKMUTVV7A", method: .accessibility,
                    cleanedBy: .rules,
                    insertedInto: "Notes")))
        // The ordinary dictation is the marker that the ledger's writes have run.
        app.render(
            .inserted(
                DictationOutcome(
                    text: "see you at noon.", method: .accessibility, cleanedBy: .rules, insertedInto: "Notes"
                )))
        try await eventually { await !ledger.rows(keeping: window).isEmpty }

        let rows = await ledger.rows(keeping: window)
        #expect(rows.filter { $0.kind == .styleMessage }.map(\.weight).reduce(0, +) == 1)
        #expect(rows.filter { $0.kind == .styleWords }.map(\.weight).reduce(0, +) == 4)
    }
}
