// Synthetic controls for combining and committing the two index snapshots.

import Foundation
import Testing

@testable import UttrflowClipboard

@Suite("Clipboard index snapshot reconciliation")
struct ClipIndexSnapshotTests {
    @Test("saved identities win, aliases normalize, and flushed use reopens with the same complete list")
    func collisionAndUseSurviveReopening() async throws {
        let folder = try TemporaryFolder()
        let now = folder.retention.now
        let saved = Clip(
            text: "Saved copy", kind: .text, copiedAt: now, lastUsedOrder: 20,
            alias: "/same", isPinned: true)
        let duplicate = Clip(
            id: saved.id, text: "History collision", kind: .text, copiedAt: now, lastUsedOrder: 99)
        let otherSaved = Clip(
            text: "Second saved", kind: .text, copiedAt: now, lastUsedOrder: 10,
            alias: "/same", isPinned: true)
        let history = Clip(text: "History row", kind: .text, copiedAt: now, lastUsedOrder: 15)
        let savedFile = await folder.store.savedFile
        try JSONEncoder().encode(ClipboardIndex(clips: [saved, otherSaved])).write(to: savedFile)
        let historyFile = folder.url.appending(path: "clipboard.json")
        try JSONEncoder().encode(ClipboardIndex(clips: [duplicate, history])).write(to: historyFile)
        let initial = await folder.store.clips(keeping: folder.retention)
        #expect(initial.map(\.id) == [saved.id, history.id, otherSaved.id])
        #expect(initial.map(\.text) == ["Saved copy", "History row", "Second saved"])
        #expect(initial.map(\.alias) == ["/same", nil, nil])
        #expect(initial.map(\.lastUsedOrder) == [20, 15, 10])
        let moved = await folder.store.markUsed(history.id, at: now, keeping: folder.retention)
        let writes = await ClipboardWriteCountTests.writes { await folder.store.flushUse() }
        #expect(writes == 2)
        let reopened = await ClipboardStore(file: historyFile).clips(keeping: folder.retention)
        #expect(reopened == moved)
        #expect(reopened.map(\.id) == [history.id, saved.id, otherSaved.id])
        #expect(reopened.map(\.lastUsedOrder) == [21, 20, 10])
    }
}
