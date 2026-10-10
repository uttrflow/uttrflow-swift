import CryptoKit
import Foundation
import UttrflowClipboard
import UttrflowCore
import UttrflowInput
import UttrflowPipeline
import UttrflowTestSupport
import Testing

@testable import Uttrflow

@MainActor
@Suite("Menu bar clipboard snapshot refresh")
struct MenuBarClipRefreshTests {
    private struct Keys: StoreKeyProviding {
        let value = SymmetricKey(size: .bits256)
        func key(createIfMissing: Bool) throws -> SymmetricKey { value }
    }

    private actor InsertionRecorder: TextInserting {
        private(set) var inserted: [String] = []

        func insert(_ text: String) async throws(TextInsertionError) -> InsertionAttempt {
            inserted.append(text)
            return InsertionAttempt(.accessibility, arrival: .confirmed)
        }
    }

    @Test("a captured clip action still inserts its clip after a newer copy shifts the list")
    func capturedClipActionUsesIdentity() async throws {
        let sandbox = Sandbox()
        let app = AppDelegate(container: sandbox.root, account: HeldSession(signedIn: true).layer)
        let store = ClipboardStore(file: ClipboardStore.defaultFile(in: sandbox.root))
        let retention = ClipRetention(days: 30, now: .now)
        let selected = Clip(text: "The clip the user chose", kind: .text, copiedAt: .now)
        _ = try await store.record(selected, keeping: retention)

        await app.readMenuClips()
        let captured = try #require(app.menuBarPresentation.clips.first?.insert.intent)

        _ = try await store.record(
            Clip(text: "A newer copy", kind: .text, copiedAt: .now.addingTimeInterval(1)),
            keeping: retention)
        await app.readMenuClips()
        let insertion = InsertionRecorder()
        app.clipInserter = insertion

        app.carryOut(captured)

        try await eventually { await insertion.inserted == [selected.text] }
    }

    @Test("a captured recent action still inserts its dictation after a newer one arrives")
    func capturedRecentActionUsesIdentity() async throws {
        let sandbox = Sandbox()
        let app = AppDelegate(container: sandbox.root, account: HeldSession(signedIn: true).layer)
        app.drawsWindows = false
        app.render(
            .inserted(
                DictationOutcome(
                    text: "The dictation the user chose", method: .accessibility, cleanedBy: .rules)))
        let captured = try #require(app.menuBarPresentation.lastDictation?.insert.intent)

        app.render(
            .inserted(
                DictationOutcome(
                    text: "A newer dictation", method: .accessibility, cleanedBy: .rules)))
        let insertion = InsertionRecorder()
        app.clipInserter = insertion

        app.carryOut(captured)

        try await eventually { await insertion.inserted == ["The dictation the user chose"] }
    }

    @Test("refreshing after a panel edit updates an already-drawn menu presentation")
    func panelEditRefreshesMenuSnapshot() async throws {
        let sandbox = Sandbox()
        let app = AppDelegate(container: sandbox.root, account: HeldSession(signedIn: true).layer)
        let store = ClipboardStore(file: ClipboardStore.defaultFile(in: sandbox.root))
        let retention = ClipRetention(days: 30, now: .now)
        let recorded = try await store.record(
            Clip(text: "before edit", kind: .text, copiedAt: .now), keeping: retention)
        let clip = try #require(recorded.first { $0.text == "before edit" })

        await app.readMenuClips()
        #expect(app.menuBarPresentation.clips.first?.title == "before edit")

        app.apply(.rewriteText(clip.id, "after edit"))

        try await eventually { app.menuBarPresentation.clips.first?.title == "after edit" }
    }

    @Test("a damaged clipboard index is announced once with its preserved location")
    func damagedIndexNotice() async throws {
        let sandbox = Sandbox()
        let file = ClipboardStore.defaultFile(in: sandbox.root)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: file)
        let app = AppDelegate(
            container: sandbox.root,
            account: HeldSession(signedIn: true).layer,
            encryptedStore: EncryptedStore(keys: Keys()))

        await app.readMenuClips()
        let notice = try #require(app.actionNotice)
        #expect(notice.message.contains("clipboard.v1.json.unreadable-"))
        #expect(notice.message.contains(file.deletingLastPathComponent().path))

        await app.readMenuClips()
        #expect(app.actionNotice == notice)
    }

    @Test("a newer clipboard payload is announced as read-only")
    func futureClipboardIndexNotice() async throws {
        let sandbox = Sandbox()
        let file = ClipboardStore.defaultFile(in: sandbox.root)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"version":99,"clips":[]}"#.utf8).write(to: file)
        let app = AppDelegate(container: sandbox.root, account: HeldSession(signedIn: true).layer)

        await app.readMenuClips()

        let notice = try #require(app.actionNotice)
        #expect(notice.message.contains("version 99"))
        #expect(notice.message.contains("read-only"))
        #expect(notice.message.contains("Update Uttrflow"))
    }

    @Test("a partial clipboard recovery reports the skipped clip count and quarantine location")
    func partialIndexNotice() async throws {
        let sandbox = Sandbox()
        let file = ClipboardStore.defaultFile(in: sandbox.root)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let readable = Clip(text: "still available", kind: .text, copiedAt: .now)
        var data = try JSONEncoder().encode([readable])
        data.removeLast()
        data.append(contentsOf: [0x2C])
        data.append(
            contentsOf: #"{"text":"malformed clip","kind":"text","copiedAt":1700000060.0,"origin":"copied"}"#
                .utf8)
        data.append(contentsOf: [0x5D])
        try data.write(to: file)
        let app = AppDelegate(
            container: sandbox.root,
            account: HeldSession(signedIn: true).layer,
            encryptedStore: EncryptedStore(
                keys: Keys(), markerURL: sandbox.root.appending(path: "legacy-migration.marker")))

        await app.readMenuClips()

        let notice = try #require(app.actionNotice)
        #expect(notice.message.contains("1 clipboard clip could not be read."))
        #expect(notice.message.contains(".quarantine-"))
        #expect(app.menuBarPresentation.clips.first?.title == "still available")
    }
}
