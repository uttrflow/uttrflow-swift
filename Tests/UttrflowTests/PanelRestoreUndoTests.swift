import Foundation
import UttrflowClipboard
import UttrflowSettings
import UttrflowUX
import Testing

@testable import Uttrflow

@MainActor
@Suite("Clipboard undo in the app", .serialized)
struct PanelRestoreUndoTests {
    @Test("the restore action keeps the new alias and tells the user", .bug(id: 3750))
    func restoreActionReportsAliasConflict() async throws {
        let sandbox = Sandbox()
        let retention = ClipRetention(days: 7, now: .now)
        let store = ClipboardStore(file: ClipboardStore.defaultFile(in: sandbox.root))
        let deleted = Clip(text: "older copy", kind: .text, copiedAt: .now, alias: "pg")
        try await store.record(deleted, keeping: retention)
        try await store.delete(deleted.id, keeping: retention)

        let holder = Clip(text: "newer copy", kind: .text, copiedAt: .now, alias: "pg")
        try await store.record(holder, keeping: retention)

        let app = AppDelegate(container: sandbox.root, account: HeldSession(signedIn: true).layer)
        app.drawsWindows = false
        app.settingsChanged(to: Settings(clipboardEnabled: false))
        await app.perform(.clipboard)
        defer {
            if app.isQuickPanelOpen { Task { await app.perform(.clipboard) } }
        }
        #expect(app.isQuickPanelOpen)

        app.apply(.restore(deleted))
        for _ in 0..<100 where app.panel?.notice?.message != PanelNotice.restoreWithoutAlias.message {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(app.panel?.notice?.message == PanelNotice.restoreWithoutAlias.message)
        let restoredStore = ClipboardStore(file: ClipboardStore.defaultFile(in: sandbox.root))
        let clips = await restoredStore.clips(keeping: retention)
        #expect(clips.first { $0.id == holder.id }?.alias == "pg")
        #expect(clips.first { $0.id == deleted.id }?.alias == nil)

        let cleanRestore = Clip(text: "a clip without a competing name", kind: .text, copiedAt: .now)
        app.apply(.restore(cleanRestore))
        for _ in 0..<100 where !(app.panel?.clips.contains { $0.id == cleanRestore.id } ?? false) {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(app.panel?.notice == nil)

        await app.perform(.clipboard)
        #expect(!app.isQuickPanelOpen)
    }
}
