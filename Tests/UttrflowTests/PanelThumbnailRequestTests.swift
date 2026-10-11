import AppKit
import Dispatch
import Synchronization
import Testing

@testable import Uttrflow

@MainActor
@Suite("Thumbnail requests across decode completion", .timeLimit(.minutes(1)))
struct PanelThumbnailRequestTests {
    @Test(
        "Preparing and reading across a suspended decode asks once at the thumbnail size", arguments: 0..<50)
    func oneRequestAcrossCompletion(repetition: Int) async throws {
        let file = URL(fileURLWithPath: "/tmp/uttrflow-thumbnail-request-\(repetition).png")
        let sizes = Mutex<[Int]>([])
        let started = AsyncStream<Void>.makeStream()
        let finish = DispatchGroup()
        finish.enter()
        let source = PanelThumbnailSource { _, maxPixel in
            sizes.withLock { $0.append(maxPixel) }
            started.continuation.yield(())
            // The test releases the decoder after checking requests while its result is pending.
            finish.wait()
            return PanelThumbnailsTests.bitmap()
        }
        let thumbnails = PanelThumbnails(source: source)
        thumbnails.prepare(file)
        var events = started.stream.makeAsyncIterator()
        _ = await events.next()

        for _ in 0..<3 {
            thumbnails.prepare(file)
            #expect(thumbnails.thumbnail(for: file) == nil)
        }
        finish.leave()
        await thumbnails.waitForIdle(file: file)

        #expect(thumbnails.cached(file) != nil)
        for _ in 0..<3 {
            thumbnails.prepare(file)
            #expect(thumbnails.thumbnail(for: file) === thumbnails.cached(file))
        }
        await thumbnails.waitForIdle(file: file)
        #expect(sizes.withLock { $0 } == [PanelThumbnails.maxPixel])
        started.continuation.finish()
    }
}
