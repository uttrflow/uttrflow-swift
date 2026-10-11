// Tests for the disk bound on the pictures the user keeps.

import Foundation
import Testing

@testable import UttrflowClipboard

/// A write that would take kept pictures past `ClipboardBudget.disk` is refused. See Docs/clipboard-budget.md.
@Suite("What happens when kept pictures reach the disk bound")
struct KeptPictureBoundTests {
    private func picture(_ name: String, at offset: TimeInterval = 0) -> Clip {
        Clip(
            text: "", kind: .image, copiedAt: noon.addingTimeInterval(offset),
            source: "Screenshot", origin: .copied,
            image: ClipImage(file: "\(name).png", width: 1, height: 1, bytes: 50, sha: name))
    }

    /// Records 50-byte pictures and pins each one.
    private func pinned(
        _ names: [String], in store: ClipboardStore, from offset: TimeInterval = 0
    ) async throws -> [Clip] {
        var clips: [Clip] = []
        for (index, name) in names.enumerated() {
            let clip = picture(name, at: offset + Double(index))
            try await store.record(clip, keeping: week())
            try await store.setPinned(true, of: clip.id, keeping: week())
            clips.append(await store.clips(keeping: week()).first { $0.id == clip.id } ?? clip)
        }
        return clips
    }

    private func makeStore(disk: Int, at file: borrowing TemporaryFile) -> ClipboardStore {
        ClipboardStore(file: file.url, budget: .standard.limiting(items: 100, disk: disk))
    }

    @Test("undoing a kept picture's delete past the bound is refused, and nothing kept is lost")
    func restorePastTheBoundIsRefused() async throws {
        let file = TemporaryFile()
        let store = makeStore(disk: 200, at: file)
        let kept = try await pinned(["a", "b", "c", "d"], in: store)
        try await store.delete(kept[0].id, keeping: week(), holdingPicture: true)
        let refill = try await pinned(["e"], in: store, from: 10)

        await #expect(throws: ClipboardStoreError.keptPicturesFull) {
            try await store.restore(kept[0], keeping: week())
        }

        let clips = await store.clips(keeping: week())
        #expect(Set(clips.filter(\.isKept).map(\.id)) == Set((kept.dropFirst() + refill).map(\.id)))
    }

    @Test("an undo that fits is restored as it was")
    func restoreWithinTheBoundIsKept() async throws {
        let file = TemporaryFile()
        let store = makeStore(disk: 200, at: file)
        let kept = try await pinned(["a", "b", "c", "d"], in: store)
        try await store.delete(kept[0].id, keeping: week(), holdingPicture: true)

        let clips = try await store.restore(kept[0], keeping: week())

        #expect(clips.filter(\.isKept).count == 4)
    }

    @Test("pinning still makes room by evicting unkept pictures, least recently used first")
    func pinWithinTheBoundStillEvictsUnkept() async throws {
        let file = TemporaryFile()
        let store = makeStore(disk: 200, at: file)
        let older = picture("older", at: 1)
        try await store.record(older, keeping: week())
        try await store.record(picture("newer", at: 2), keeping: week())
        _ = try await pinned(["a", "b", "c"], in: store, from: 10)

        let clips = await store.clips(keeping: week())

        #expect(clips.filter(\.isKept).count == 3)
        #expect(clips.compactMap(\.image?.bytes).reduce(0, +) <= 200)
        #expect(!clips.contains { $0.id == older.id }, "the least recently used unkept picture went")
    }

    @Test("kept pictures already past the bound are never deleted, and can still be edited")
    func existingOverflowStays() async throws {
        let file = TemporaryFile()
        let kept = try await pinned(["a", "b", "c", "d"], in: makeStore(disk: 500, at: file))
        let tight = makeStore(disk: 100, at: file)

        let renamed = try await tight.setAlias("/shot", of: kept[1].id, keeping: week())

        #expect(Set(renamed.filter(\.isKept).map(\.id)) == Set(kept.map(\.id)))
        #expect(renamed.first { $0.id == kept[1].id }?.alias == "/shot")
    }

    @Test("a zero disk bound turns the refusal off")
    func zeroBoundAdmitsEveryRestore() async throws {
        let file = TemporaryFile()
        let store = makeStore(disk: 0, at: file)
        let kept = try await pinned(["a", "b"], in: store)
        try await store.delete(kept[0].id, keeping: week(), holdingPicture: true)
        _ = try await pinned(["c", "d", "e"], in: store, from: 10)

        let clips = try await store.restore(kept[0], keeping: week())

        #expect(clips.filter(\.isKept).count == 5)
    }

    @Test("the refusal tells the user what to do")
    func refusalExplainsItself() {
        #expect(ClipboardStoreError.keptPicturesFull.userMessage.contains("Unpin or delete"))
    }
}
