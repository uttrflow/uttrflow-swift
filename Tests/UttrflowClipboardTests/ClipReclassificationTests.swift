// Synthetic migration controls across cooperative classifier batch boundaries.

import Foundation
import Testing

@testable import UttrflowClipboard
@testable import UttrflowCore

@Suite("Clipboard classification across batch boundaries")
struct ClipReclassificationTests {
    @Test("all 201 legacy records retain identity and text while their detector version advances")
    func everyBatchReachesTheIndex() async throws {
        let file = TemporaryFile()
        let now = Date.now
        let original = (0..<201).map { index in
            Clip(
                text: "func load() { return value }", kind: .text,
                copiedAt: now.addingTimeInterval(-Double(index)))
        }
        try FileManager.default.createDirectory(
            at: file.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(original).write(to: file.url)
        let store = ClipboardStore(file: file.url)
        let retention = ClipRetention(days: 30, now: now)

        let initial = await store.clips(keeping: retention)
        #expect(initial.map(\.id) == original.map(\.id))
        #expect(initial.map(\.kind) == Array(repeating: .text, count: 201))
        await store.waitForClassifierMigrations()

        let classified = await store.clips(keeping: retention)
        #expect(classified.map(\.id) == original.map(\.id))
        #expect(classified.map(\.text) == original.map(\.text))
        #expect(classified.map(\.kind) == Array(repeating: .code, count: 201))
        let persisted = try JSONDecoder().decode(ClipboardIndex.self, from: Data(contentsOf: file.url))
        #expect(persisted.classifierVersion == ClipboardIndex.currentClassifierVersion)
        #expect(persisted.clips == classified)
    }
}

@Suite("Detector rewrite without files")
struct ClipReclassificationRewriteTests {
    @Test("a pass that covers every current text keeps live eviction order")
    func coveredPassKeepsLiveOrder() {
        let clip = Clip(text: "let a = 1", kind: .text, copiedAt: .now)
        let live = clip.orderedForEviction(7)
        let detected = clip.reclassified(as: ClipClassification(kind: .code, language: nil))
        var secrecy = ClipSecrecyOverrides(file: TemporaryFile().url, encryptedStore: nil)
        let rewritten = ClipReclassification.rewrite(
            [detected], from: [clip], into: [clip], liveOrder: [live], secrecy: &secrecy)
        #expect(rewritten?.first?.kind == .code)
        #expect(rewritten?.first?.lastUsedOrder == 7)
    }

    @Test("a clip that changed after the snapshot leaves the index for the next launch")
    func changedTextWritesNothing() {
        let old = Clip(text: "one", kind: .text, copiedAt: .now)
        var changed = old
        changed.text = "two"
        var secrecy = ClipSecrecyOverrides(file: TemporaryFile().url, encryptedStore: nil)
        let rewritten = ClipReclassification.rewrite(
            [old], from: [old], into: [changed], liveOrder: [], secrecy: &secrecy)
        #expect(rewritten == nil)
    }
}
