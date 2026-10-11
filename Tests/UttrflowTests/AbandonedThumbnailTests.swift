// A decode already in flight must not restore a row that disappeared.

import AppKit
import Foundation
import Synchronization
import Testing
import UttrflowTestSupport

@testable import Uttrflow

@MainActor
@Suite("Abandoned thumbnail results", .serialized, .timeLimit(.minutes(1)))
struct AbandonedThumbnailTests {
    private final class HeldDecode: @unchecked Sendable {
        private let state = Mutex(0)
        private let gate = DispatchSemaphore(value: 0)
        var calls: Int { state.withLock { $0 } }
        func release() { gate.signal() }
        func load() -> NSImage {
            let first = state.withLock { count in
                count += 1
                return count == 1
            }
            if first { gate.wait() }
            return NSImage(size: NSSize(width: 8, height: 8))
        }
    }

    @Test("an abandoned running decode is discarded and the next visible request can retry")
    func disappearingRowDropsTheRunningResult() async throws {
        let source = HeldDecode()
        defer { source.release() }
        let thumbnails = PanelThumbnails(source: PanelThumbnailSource { _, _ in source.load() })
        let file = FileManager.default.temporaryDirectory.appending(
            path: "thumbnail-\(UUID().uuidString).png")
        thumbnails.prepare(file)
        try await eventually { source.calls == 1 }
        thumbnails.cancel(file)
        source.release()
        await thumbnails.waitForIdle(file: file)
        #expect(!thumbnails.known.keys.contains(file))
        #expect(thumbnails.bytesHeld == 0)
        thumbnails.prepare(file)
        await thumbnails.waitForIdle(file: file)
        #expect(source.calls == 2)
        #expect(thumbnails.cached(file) != nil)
    }
}
