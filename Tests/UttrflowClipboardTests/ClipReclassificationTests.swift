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
