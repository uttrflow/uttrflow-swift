// Tests that the paste and copy shortcuts lose the last dictation once it is reset or deleted.

import Foundation
import Synchronization
import UttrflowCore
import UttrflowClipboard
import UttrflowHistory
import UttrflowInput
import UttrflowPipeline
import UttrflowSettings
import UttrflowUX
import Testing

@testable import Uttrflow

@MainActor
@Suite("The last transcript is forgotten with the dictation it came from")
struct LastTranscriptForgetTests {
    private actor InsertionRecorder: TextInserting {
        private(set) var inserted: [String] = []

        func insert(_ text: String) async throws(TextInsertionError) -> InsertionAttempt {
            inserted.append(text)
            return InsertionAttempt(.accessibility, arrival: .confirmed)
        }
    }

    private func dictated(_ text: String, in sandbox: borrowing Sandbox) -> AppDelegate {
        let app = AppDelegate(container: sandbox.root, account: HeldSession(signedIn: true).layer)
        app.render(.inserted(DictationOutcome(text: text, method: .accessibility, cleanedBy: .rules)))
        return app
    }

    @Test("words inserted without clean-up say so, and tidied words do not")
    func untidiedInsertionIsAnnounced() {
        let sandbox = Sandbox()
        let app = dictated("Sample words", in: sandbox)
        #expect(app.actionNotice == nil)

        app.render(
            .inserted(DictationOutcome(text: "um sample", method: .accessibility, cleanedBy: .untidied)))

        #expect(app.actionNotice == MainNotice.cleanUpSkipped(by: .untidied))
    }

    @Test("a reset that clears history forgets the last transcript")
    func resetForgets() {
        let sandbox = Sandbox()
        let app = dictated("Sample words", in: sandbox)
        #expect(app.lastTranscript == "Sample words")

        app.forget(after: .everything)

        #expect(app.lastTranscript == nil)
        #expect(app.lastTranscriptID == nil)
    }

    @Test("a reset that clears the clipboard withdraws its panel undo offer")
    func resetWithdrawsPanelUndo() {
        let sandbox = Sandbox()
        let app = AppDelegate(container: sandbox.root)
        let clip = Clip(text: "Private words", kind: .text, copiedAt: .now, source: nil)
        _ = app.undoOffer.offer([clip])
        let timer = Task { _ = try? await Task.sleep(for: .seconds(30)) }
        app.undoTask = timer

        app.forget(after: .everything)

        #expect(app.undoOffer.clip == nil)
        #expect(app.undoOffer.pendingDelete == nil)
        #expect(app.undoOffer.claimForRestore()?.clip == nil)
        #expect(timer.isCancelled)
        #expect(app.undoTask == nil)
    }

    @Test("deleting the dictation it came from forgets the last transcript")
    func deleteForgets() throws {
        let sandbox = Sandbox()
        let app = dictated("Sample words", in: sandbox)
        let id = try #require(app.lastTranscriptID)

        app.carryOut(.forgetDictation(id))

        #expect(app.lastTranscript == nil)
        #expect(app.lastTranscriptID == nil)
    }

    @Test("deleting another dictation keeps the last transcript")
    func deleteOtherKeeps() {
        let sandbox = Sandbox()
        let app = dictated("Sample words", in: sandbox)

        app.carryOut(.forgetDictation(UUID()))

        #expect(app.lastTranscript == "Sample words")
    }

    @Test("paste-last inserts the newest kept record after relaunch")
    func relaunchThenPasteLast() async throws {
        let sandbox = Sandbox()
        let history = DictationHistoryStore(
            file: DictationHistoryStore.defaultFile(in: sandbox.root))
        let newest = DictationRecord(text: "Newest words", when: .now)
        try await history.append(newest, keeping: Retention(days: 7, now: .now))

        let session = HeldSession(signedIn: true)
        let app = AppDelegate(container: sandbox.root, account: session.layer)
        let insertion = InsertionRecorder()
        let clipboardRoute = InsertionRecorder()
        app.lastTranscriptInserter = insertion
        app.clipInserter = clipboardRoute
        await app.restoreLastTranscript()
        await app.perform(.pasteLastTranscript)

        #expect(await insertion.inserted == ["Newest words"])
        #expect(await clipboardRoute.inserted.isEmpty)
        #expect(app.lastTranscriptID == newest.id)
    }

    @Test(
        "both shortcuts refuse a dictation that has aged past retention",
        arguments: [ShortcutAction.pasteLastTranscript, ShortcutAction.copyLastTranscript])
    func agedPastRetentionIsForgotten(action: ShortcutAction) async throws {
        let sandbox = Sandbox()
        let history = DictationHistoryStore(
            file: DictationHistoryStore.defaultFile(in: sandbox.root))
        let aged = DictationRecord(text: "Aged words", when: .now.addingTimeInterval(-3 * 86_400))
        try await history.append(aged, keeping: Retention(days: 30, now: .now))
        let session = HeldSession(signedIn: true)
        let app = AppDelegate(container: sandbox.root, account: session.layer)
        app.settingsChanged(to: Settings(transcriptRetentionDays: 30))
        let insertion = InsertionRecorder()
        app.clipInserter = insertion
        await app.restoreLastTranscript()
        #expect(app.lastTranscriptID == aged.id)

        app.settingsChanged(to: Settings(transcriptRetentionDays: 1))
        await app.perform(action)

        #expect(await insertion.inserted.isEmpty)
        #expect(app.lastTranscript == nil)
        #expect(app.actionNotice?.message.hasPrefix("There is no transcript to") == true)
    }

    @Test(
        "both shortcuts say so when there is nothing to put back",
        arguments: [
            (ShortcutAction.pasteLastTranscript, "There is no transcript to paste yet."),
            (ShortcutAction.copyLastTranscript, "There is no transcript to copy yet."),
        ])
    func nothingToPutBackIsSaid(action: ShortcutAction, message: String) async {
        let sandbox = Sandbox()
        let session = HeldSession(signedIn: true)
        let app = AppDelegate(container: sandbox.root, account: session.layer)

        await app.perform(action)

        #expect(app.actionNotice?.message == message)
    }

    @Test("copy-last conceals a secret transcript")
    func copyLastTranscriptConcealsSecrets() async throws {
        let sandbox = Sandbox()
        let secret = "password=demo1"
        let history = DictationHistoryStore(
            file: DictationHistoryStore.defaultFile(in: sandbox.root))
        try await history.append(
            DictationRecord(text: secret, when: .now), keeping: Retention(days: 30, now: .now))
        let pasteboard = MarkerRecordingPasteboard()
        let app = AppDelegate(
            container: sandbox.root, account: HeldSession(signedIn: true).layer, pasteboard: pasteboard)
        await app.restoreLastTranscript()

        await app.perform(.copyLastTranscript)

        #expect(pasteboard.markers[secret] == .concealed)
    }

    @Test("copy-last marks an ordinary transcript transient")
    func copyLastTranscriptMarksOrdinaryTextTransient() async {
        let sandbox = Sandbox()
        let transcript = "Dictated words"
        let pasteboard = MarkerRecordingPasteboard()
        let app = AppDelegate(
            container: sandbox.root, account: HeldSession(signedIn: true).layer, pasteboard: pasteboard)
        app.render(inserted(transcript))

        await app.perform(.copyLastTranscript)

        #expect(pasteboard.markers[transcript] == .transient)
    }

    private func failed(_ text: String, secure: Bool = false) -> DictationState {
        .failed(
            DictationFailure(
                message: "Not inserted", recovery: .retry, severity: .recoverable,
                transcript: text, intoSecureField: secure))
    }

    private func inserted(_ text: String, secure: Bool = false) -> DictationState {
        .inserted(
            DictationOutcome(
                text: text, method: .accessibility, cleanedBy: .rules, intoSecureField: secure))
    }

    @Test("a failed insertion after an inserted one is what both shortcuts act on")
    func insertedThenFailed() async throws {
        let sandbox = Sandbox()
        let app = dictated("Older words", in: sandbox)
        let olderID = try #require(app.lastTranscriptID)
        let insertion = InsertionRecorder()
        app.lastTranscriptInserter = insertion

        app.render(failed("Newer words"))
        await app.perform(.pasteLastTranscript)

        #expect(app.lastTranscript == "Newer words")
        #expect(await insertion.inserted == ["Newer words"])
        #expect(app.lastTranscriptID != olderID)
    }

    @Test("an inserted dictation after a failed one replaces it")
    func failedThenInserted() {
        let sandbox = Sandbox()
        let app = AppDelegate(container: sandbox.root)

        app.render(failed("Salvaged words"))
        app.render(inserted("Inserted words"))

        #expect(app.lastTranscript == "Inserted words")
    }

    @Test("a secure field keeps nothing, so the next dictation is the last transcript")
    func secureThenInserted() {
        let sandbox = Sandbox()
        let app = dictated("Older words", in: sandbox)

        app.render(inserted("Hidden words", secure: true))
        #expect(app.lastTranscript == "Older words")
        app.render(failed("Hidden failed words", secure: true))
        #expect(app.lastTranscript == "Older words")
        app.render(inserted("Newer words"))

        #expect(app.lastTranscript == "Newer words")
    }
}

private final class MarkerRecordingState: Sendable {
    private struct Value: Sendable {
        var text: String?
        var markers: [String: PasteboardMarkers] = [:]
    }

    private let value = Mutex(Value())

    var text: String? { value.withLock { $0.text } }
    var markers: [String: PasteboardMarkers] { value.withLock { $0.markers } }

    func write(_ text: String, marker: PasteboardMarkers) -> PasteboardWriteResult {
        value.withLock {
            $0.text = text
            $0.markers[text] = marker
        }
        return .written(changeCount: nil)
    }
}

private struct MarkerRecordingPasteboard: Pasteboard {
    private let state = MarkerRecordingState()
    var markers: [String: PasteboardMarkers] { state.markers }

    func text() -> String? { state.text }
    func setText(_ text: String) -> PasteboardWriteResult { state.write(text, marker: []) }
    func setConcealedText(_ text: String) -> PasteboardWriteResult {
        state.write(text, marker: .concealed)
    }
    func writeTransientText(_ text: String, richText: String?) -> PasteboardWriteResult {
        state.write(text, marker: .transient)
    }
    func writeConcealedText(_ text: String) -> PasteboardWriteResult {
        state.write(text, marker: .concealed)
    }
    func setImage(_ data: Data) -> PasteboardWriteResult { .refused }
}
