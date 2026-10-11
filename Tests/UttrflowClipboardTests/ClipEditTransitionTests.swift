// Synthetic controls for edit transitions between saved clips and ordinary history.

import Foundation
import Testing

@testable import UttrflowClipboard

@Suite("Clipboard edit transitions")
struct ClipEditTransitionTests {
    @Test("batch unkeeping preserves other markers and single unkeeping advances the same order")
    func mixedMarkersRetainTransitionOrder() async throws {
        let folder = try TemporaryFolder()
        let old = noon.addingTimeInterval(-30 * 86_400)
        let tagged = Clip(
            text: "tagged", kind: .text, copiedAt: old, lastUsedOrder: 30,
            tags: ["keep"], category: "Work")
        let second = Clip(text: "second", kind: .text, copiedAt: old, lastUsedOrder: 20, category: "Work")
        let third = Clip(text: "third", kind: .text, copiedAt: old, lastUsedOrder: 10, category: "Work")
        let saved = await folder.store.savedFile
        try JSONEncoder().encode(ClipboardIndex(clips: [tagged, second, third])).write(to: saved)
        let batchWrites = try await ClipboardWriteCountTests.writes {
            try await folder.store.moveCategory("Work", to: nil, keeping: week())
        }
        let moved = await folder.store.clips(keeping: week())
        #expect(batchWrites == 3)
        #expect(moved.map(\.id) == [third.id, second.id, tagged.id])
        #expect(moved.map(\.lastUsedOrder) == [32, 31, 30])
        #expect(moved.map(\.copiedAt) == [noon, noon, old])
        #expect(moved.map(\.isKept) == [false, false, true])
        let editWrites = try await ClipboardWriteCountTests.writes {
            try await folder.store.setLabels(alias: nil, tags: [], of: tagged.id, keeping: week())
        }
        let changed = await folder.store.clips(keeping: week())
        #expect(editWrites == 2)
        #expect(changed.map(\.id) == [tagged.id, third.id, second.id])
        #expect(changed.map(\.lastUsedOrder) == [33, 32, 31])
        #expect(changed.allSatisfy { !$0.isKept && $0.copiedAt == noon })
        let reopened = ClipboardStore(file: folder.url.appending(path: "clipboard.json"))
        #expect(await reopened.clips(keeping: week()) == changed)
    }

    @Test("unkeeping at the maximum eviction order saturates without losing the clip")
    func unkeepingSaturatesOrder() async throws {
        let folder = try TemporaryFolder()
        let clip = Clip(
            text: "saturated", kind: .text, copiedAt: noon.addingTimeInterval(-30 * 86_400),
            lastUsedOrder: .max, isPinned: true)
        try JSONEncoder().encode(ClipboardIndex(clips: [clip])).write(to: await folder.store.savedFile)
        let changed = try await folder.store.setPinned(false, of: clip.id, keeping: week())
        #expect(changed.map(\.lastUsedOrder) == [.max])
        #expect(changed.first?.copiedAt == noon)
        #expect(changed.first?.isKept == false)
        let reopened = ClipboardStore(file: folder.url.appending(path: "clipboard.json"))
        #expect(await reopened.clips(keeping: week()) == changed)
    }
}
