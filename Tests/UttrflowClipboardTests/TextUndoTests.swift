// Tests that a deleted text clip comes back whole for as long as an undo can bring it back —
// the text-side counterpart of PictureUndoTests, across pastes made before the undo.

import Foundation
import Testing

@testable import UttrflowClipboard

@Suite("Undoing the delete of a text clip")
struct TextUndoTests {
    private func clip(_ text: String, at offset: TimeInterval = 0) -> Clip {
        Clip(text: text, kind: .text, copiedAt: noon.addingTimeInterval(offset), source: "Notes")
    }

    /// The undo window: the user pastes two other clips before bringing the deleted one back.
    @Test("two pastes before the undo leave the deleted clip's return whole", .bug(id: 3668))
    func pastesBeforeTheUndoLeaveTheReturnWhole() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url, useFlushDelay: .seconds(3_600))
        let first = clip("first", at: -300)
        let second = clip("second", at: -240)
        let subject = clip("the door code", at: -60)
        for one in [first, second, subject] { try await store.record(one, keeping: week()) }
        try await store.setAlias("code", of: subject.id, keeping: week())
        try await store.setPinned(true, of: subject.id, keeping: week())

        let deleted = try #require(await store.clips(keeping: week()).first { $0.id == subject.id })
        _ = try await store.delete(deleted.id, keeping: week())
        #expect(await store.clips(keeping: week()).allSatisfy { $0.id != deleted.id })

        // The pastes happen while the undo is still available; their uses are held, not yet written.
        _ = await store.markUsed(first.id, at: noon.addingTimeInterval(600), keeping: week())
        _ = await store.markUsed(second.id, at: noon.addingTimeInterval(660), keeping: week())

        _ = try await store.restore(deleted, keeping: week())

        let reopened = await ClipboardStore(file: file.url).clips(keeping: week())
        let back = try #require(reopened.first { $0.id == deleted.id })
        #expect(back.alias == "code", "the name came back with it")
        #expect(back.isPinned, "the pin came back with it")
        #expect(reopened.count == 3, "the pastes added nothing")
        #expect(reopened.prefix(2).map(\.id) == [second.id, first.id], "the pastes kept their order")
    }

    /// The same when the pastes reached the disk before the undo, rather than travelling with it.
    @Test("a flushed paste before the undo still leaves the deleted clip whole", .bug(id: 3668))
    func flushedPastesBeforeTheUndoLeaveTheReturnWhole() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url, useFlushDelay: .seconds(3_600))
        let pasted = clip("pasted", at: -300)
        let subject = clip("the door code", at: -60)
        for one in [pasted, subject] { try await store.record(one, keeping: week()) }
        try await store.setCategory("Work", of: subject.id, keeping: week())

        let deleted = try #require(await store.clips(keeping: week()).first { $0.id == subject.id })
        _ = try await store.delete(deleted.id, keeping: week())
        _ = await store.markUsed(pasted.id, at: noon.addingTimeInterval(600), keeping: week())
        await store.flushUse()

        _ = try await store.restore(deleted, keeping: week())

        let reopened = await ClipboardStore(file: file.url).clips(keeping: week())
        let back = try #require(reopened.first { $0.id == deleted.id })
        #expect(back.category == "Work", "the collection came back with it")
        #expect(reopened.count == 2)
        #expect(reopened.first?.id == pasted.id, "the flushed paste kept its place")
    }
}
