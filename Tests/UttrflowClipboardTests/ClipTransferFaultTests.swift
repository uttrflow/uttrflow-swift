// Tests that a clip moving between the two files survives either write being refused.

import Foundation
import Testing

@testable import UttrflowClipboard

/// Pinning and unpinning move a clip between files, and a refused write must never lose it.
@Suite("A clip moving between the two files survives a refused write")
struct ClipTransferFaultTests {
    /// Which file the disk refuses to replace.
    enum Refused: String, CaseIterable { case history, saved }

    /// Which way the clip moves.
    enum Direction: String, CaseIterable { case pin, unpin }

    private func clip(_ text: String, at offset: TimeInterval) -> Clip {
        Clip(
            text: text, kind: .text, copiedAt: noon.addingTimeInterval(offset), source: "Notes")
    }

    /// Marks a file immutable, which refuses both its atomic replacement and its removal.
    private func lock(_ url: URL, _ locked: Bool) throws {
        try FileManager.default.setAttributes(
            [.immutable: locked], ofItemAtPath: url.path(percentEncoded: false))
    }

    @Test(
        "reopening finds exactly one copy of the clip",
        arguments: Direction.allCases, Refused.allCases)
    func oneDurableCopy(_ direction: Direction, _ refused: Refused) async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url)
        let subject = clip("the moving clip", at: 60)
        let neighbour = clip("already saved", at: 0)
        try await store.record(neighbour, keeping: week())
        try await store.setPinned(true, of: neighbour.id, keeping: week())
        try await store.record(subject, keeping: week())
        try await store.record(clip("history filler", at: 120), keeping: week())
        if direction == .unpin {
            try await store.setPinned(true, of: subject.id, keeping: week())
        }

        let target = refused == .history ? file.url : await store.savedFile
        try lock(target, true)
        defer { try? lock(target, false) }

        await #expect(throws: ClipboardStoreError.couldNotWrite) {
            try await store.setPinned(direction == .pin, of: subject.id, keeping: week())
        }

        try lock(target, false)
        let reopened = await ClipboardStore(file: file.url).clips(keeping: week())
        #expect(reopened.filter { $0.id == subject.id }.count == 1)
        #expect(reopened.filter { $0.id == neighbour.id }.count == 1)
    }

    /// The copy left in the history by an interrupted move is cleared by the next write that succeeds.
    @Test("the next successful write leaves the clip in one file")
    func nextWriteTidies() async throws {
        let file = TemporaryFile()
        let store = ClipboardStore(file: file.url)
        let subject = clip("the moving clip", at: 60)
        try await store.record(subject, keeping: week())
        try await store.record(clip("history filler", at: 120), keeping: week())
        let saved = await store.savedFile

        // The saved file is written and the history is not, as a pin interrupted between the two.
        try await store.setPinned(true, of: subject.id, keeping: week())
        let pinned = try Data(contentsOf: saved)
        try await store.setPinned(false, of: subject.id, keeping: week())
        try pinned.write(to: saved)

        let reopened = ClipboardStore(file: file.url)
        #expect(await reopened.clips(keeping: week()).filter { $0.id == subject.id }.count == 1)
        try await reopened.record(clip("a new copy", at: 180), keeping: week())

        let history = try JSONDecoder().decode([Clip].self, from: try Data(contentsOf: file.url))
        #expect(!history.contains { $0.id == subject.id })
    }
}
