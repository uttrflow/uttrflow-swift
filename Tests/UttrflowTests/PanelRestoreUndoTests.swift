import Foundation
import UttrflowClipboard
import UttrflowSettings
import UttrflowUX
import Testing

@testable import Uttrflow

@MainActor
@Suite("Clipboard undo in the app", .serialized)
struct PanelRestoreUndoTests {
    @Test("the undo restore keeps the new alias and tells the user", .bug(id: 3750))
    func restoreActionReportsAliasConflict() async throws {
        let sandbox = Sandbox()
        let retention = ClipRetention(days: 7, now: .now)
        let store = ClipboardStore(file: ClipboardStore.defaultFile(in: sandbox.root))
        let deleted = Clip(text: "older copy", kind: .text, copiedAt: .now, alias: "pg")
        try await store.record(deleted, keeping: retention)
        try await store.delete(deleted.id, keeping: retention)

        let holder = Clip(text: "newer copy", kind: .text, copiedAt: .now, alias: "pg")
        try await store.record(holder, keeping: retention)

        let notice = try await PanelUndoRestorer.restore(
            [deleted], to: store, keeping: retention)
        #expect(notice?.message == PanelNotice.restoreWithoutAlias.message)
        let clips = await store.clips(keeping: retention)
        #expect(clips.first { $0.id == holder.id }?.alias == "pg")
        #expect(clips.first { $0.id == deleted.id }?.alias == nil)

        let cleanRestore = Clip(text: "a clip without a competing name", kind: .text, copiedAt: .now)
        let cleanNotice = try await PanelUndoRestorer.restore(
            [cleanRestore], to: store, keeping: retention)
        #expect(cleanNotice == nil)
        #expect(await store.clips(keeping: retention).contains { $0.id == cleanRestore.id })
    }

    @Test("undoing an edit writes the clip's old text back", .bug(id: 5481))
    func undoEditRestoresText() async throws {
        let sandbox = Sandbox()
        let retention = ClipRetention(days: 7, now: .now)
        let store = ClipboardStore(file: ClipboardStore.defaultFile(in: sandbox.root))
        let original = Clip(text: "before the edit", kind: .text, copiedAt: .now, alias: "kept")
        try await store.record(original, keeping: retention)
        _ = try await store.setText("after the edit", of: original.id, keeping: retention)
        var offer = PanelUndoOffer()
        offer.offerEdit(of: original.id, previousText: original.text)
        let claimed = offer.claimForRestore()
        let claim = try #require(claimed)

        let notice = try await PanelUndoRestorer.restore(claim, to: store, keeping: retention)

        #expect(notice == nil)
        let restored = await store.clips(keeping: retention).first { $0.id == original.id }
        #expect(restored?.text == "before the edit")
        #expect(restored?.alias == "kept")
    }
}
