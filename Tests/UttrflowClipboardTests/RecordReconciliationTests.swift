// Synthetic controls for collision handling across arrival, undo and reopening.

import Foundation
import Testing

@testable import UttrflowClipboard

@Suite("Clipboard record reconciliation")
struct RecordReconciliationTests {
    @Test("undo merges a newer duplicate without stealing an alias and repeats retain those choices")
    func duplicateUndoAndArrivalPreserveChoices() async throws {
        let folder = try TemporaryFolder()
        let store = folder.store
        let original = Clip(
            text: "repeatable copy", kind: .text, copiedAt: noon.addingTimeInterval(-60),
            alias: "/copy", tags: ["saved"], category: "Work", isPinned: true)
        try await store.record(original, keeping: week())
        try await store.delete(original.id, keeping: week())
        let holder = Clip(text: "alias holder", kind: .text, copiedAt: noon, alias: "/copy")
        try await store.record(holder, keeping: week())
        let newer = Clip(
            text: original.text, kind: .text, copiedAt: noon, richText: "<p>Latest copy</p>")
        try await store.record(newer, keeping: week())
        let restored = try await store.restoreReportingAliasConflict(original, keeping: week())
        let merged = try #require(restored.clips.first { $0.id == newer.id })
        #expect(restored.aliasWasAlreadyInUse)
        #expect(merged.alias == nil && merged.tags == original.tags && merged.category == original.category)
        #expect(merged.isPinned && merged.richText == newer.richText && merged.lastUsedOrder == 3)
        #expect(merged.timesCopied == 2)
        #expect(restored.clips.first { $0.id == holder.id }?.alias == "/copy")
        let repeated = try await store.record(
            Clip(text: original.text, kind: .text, copiedAt: noon.addingTimeInterval(1)), keeping: week())
        let arrival = try #require(repeated.first)
        #expect(repeated.map(\.id) == [newer.id, holder.id])
        #expect(arrival.tags == original.tags && arrival.category == original.category && arrival.isPinned)
        #expect(arrival.richText == newer.richText && arrival.lastUsedOrder == 4 && arrival.timesCopied == 3)
        let fastPathWrites = try await ClipboardWriteCountTests.writes {
            let unchanged = try await store.restoreReportingAliasConflict(arrival, keeping: week())
            #expect(unchanged.clips == repeated && unchanged.aliasWasAlreadyInUse == false)
        }
        #expect(fastPathWrites == 0)
        let reopened = ClipboardStore(file: folder.url.appending(path: "clipboard.json"))
        #expect(await reopened.clips(keeping: week()) == repeated)
    }
}
