// Tests for the thumbnail cache.

import AppKit
import ImageIO
import Testing
import UttrflowClipboard

@testable import Uttrflow

/// Decoding a picture is the expensive thing the panel does; what is worth testing is that it happens once and off the main thread.
@MainActor
@Suite("The pictures beside a clip")
struct PanelThumbnailsTests {
    /// The mock source is `@Sendable` so the cache can run it on a detached task; the counter is shared across that boundary.
    private final class Counter: @unchecked Sendable {
        var files: [URL] = []
        var sizes: [Int] = []
        var calls = 0
    }

    /// A picture with real pixels behind it; `NSImage(size:)` has no representation and weighs nothing.
    nonisolated static func bitmap(_ edge: Int = 68) -> NSImage {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: edge, pixelsHigh: edge, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        let image = NSImage(size: NSSize(width: edge, height: edge))
        if let rep { image.addRepresentation(rep) }
        return image
    }

    /// What one of those weighs, asked of the cache's own function so the two cannot disagree.
    static let thumbnailBytes = PanelThumbnails.bytes(of: bitmap())

    private func thumbnails(
        _ answers: [URL: NSImage] = [:], budget: Int? = nil
    ) -> (PanelThumbnails, Counter) {
        let counter = Counter()
        let source = PanelThumbnailSource { file, maxPixel in
            counter.files.append(file)
            counter.sizes.append(maxPixel)
            counter.calls += 1
            return answers[file]
        }
        return (PanelThumbnails(source: source, budget: budget ?? PanelThumbnails.defaultBudget), counter)
    }

    func file(_ name: String) -> URL {
        URL(fileURLWithPath: "/tmp/uttrflow-\(name).png")
    }

    private let file = URL(fileURLWithPath: "/tmp/uttrflow-shot.png")

    @Test("reads a picture once, however often the row is drawn")
    func decodesOnce() async {
        let (thumbnails, counter) = thumbnails([file: NSImage(size: NSSize(width: 4, height: 4))])

        thumbnails.prepare(file)
        await thumbnails.waitForIdle(file: file)
        for _ in 0..<20 { _ = thumbnails.thumbnail(for: file) }

        #expect(counter.files == [file])
    }

    /// A clip whose file has been deleted should not cost a trip to the disk on every frame.
    @Test("remembers that a picture is gone")
    func remembersAMiss() async {
        let (thumbnails, counter) = thumbnails()

        thumbnails.prepare(file)
        await thumbnails.waitForIdle(file: file)

        #expect(thumbnails.thumbnail(for: file) == nil)
        #expect(thumbnails.thumbnail(for: file) == nil)
        #expect(counter.files.count == 1)
    }

    /// A picture file restored after a failed decode is decoded again once the miss is stale.
    @Test("decodes a restored picture after remembering it was gone")
    func decodesARestoredPicture() async {
        let counter = Counter()
        let restored = Self.bitmap()
        let present = Counter()
        let source = PanelThumbnailSource { file, _ in
            counter.calls += 1
            return present.calls > 0 ? restored : nil
        }
        let thumbnails = PanelThumbnails(source: source, retryAfter: .zero)

        thumbnails.prepare(file)
        await thumbnails.waitForIdle(file: file)
        present.calls = 1

        #expect(thumbnails.thumbnail(for: file) == nil)
        await thumbnails.waitForIdle(file: file)
        #expect(thumbnails.thumbnail(for: file) === restored)
        #expect(counter.calls == 2)
    }

    /// Asked for at the size it is drawn, not the size of the screenshot.
    @Test("asks for the small version")
    func asksForAThumbnail() async {
        let (thumbnails, counter) = thumbnails()

        thumbnails.prepare(file)
        await thumbnails.waitForIdle(file: file)
        _ = thumbnails.thumbnail(for: file)

        #expect(counter.sizes == [PanelThumbnails.maxPixel])
        #expect(PanelThumbnails.maxPixel <= 96, "a 34-point square on a Retina screen")
    }

    @Test("keeps different pictures apart")
    func separateFiles() async {
        let other = URL(fileURLWithPath: "/tmp/uttrflow-other.png")
        let (thumbnails, counter) = thumbnails()

        thumbnails.prepare(file)
        await thumbnails.waitForIdle(file: file)
        thumbnails.prepare(other)
        await thumbnails.waitForIdle(file: other)
        _ = thumbnails.thumbnail(for: file)
        _ = thumbnails.thumbnail(for: other)

        #expect(Set(counter.files) == [file, other])
    }

    /// The cache miss returns nil immediately and the source load runs on a background queue, so the row draws the placeholder while the decode happens.
    @Test("miss does not block the caller while the source decodes")
    func missDoesNotBlockTheCaller() async {
        final class DecodingCounter: @unchecked Sendable {
            var calls = 0
        }
        let decoded = DecodingCounter()
        let image = NSImage(size: NSSize(width: 4, height: 4))
        let source = PanelThumbnailSource { file, _ in
            decoded.calls += 1
            // Long enough that a synchronous call would obviously block the caller.
            Thread.sleep(forTimeInterval: 0.1)
            return image
        }
        let thumbnails = PanelThumbnails(source: source, budget: 1)

        let started = Date()
        let result = thumbnails.thumbnail(for: file)
        let elapsed = Date().timeIntervalSince(started)

        // The miss returns right away; the source cost 100ms but the call did not.
        #expect(result == nil, "miss returns nil, the row draws the placeholder")
        #expect(elapsed < 0.01, "the call must not have waited for the decode: took \(elapsed)s")

        await thumbnails.waitForIdle(file: file)
        #expect(decoded.calls == 1, "the source ran exactly once, off the caller's thread")
        #expect(thumbnails.thumbnail(for: file) != nil)
    }

    /// Calling prepare twice for the same file does not run the source twice; the in-flight tracker deduplicates.
    @Test("duplicate prepares run the source once")
    func duplicatePrepares() async {
        let (thumbnails, counter) = thumbnails([file: NSImage(size: NSSize(width: 4, height: 4))])

        thumbnails.prepare(file)
        thumbnails.prepare(file)
        thumbnails.prepare(file)
        await thumbnails.waitForIdle(file: file)

        #expect(counter.files == [file])
    }
}

/// What the cache costs when never emptied; room is measured in whole thumbnails.
@MainActor
@Suite("What the picture cache lets go of")
struct PanelThumbnailsCapacityTests {
    private final class Counter: @unchecked Sendable { var files: [URL] = [] }

    private func thumbnails(room pictures: Int) -> (PanelThumbnails, Counter) {
        let counter = Counter()
        let source = PanelThumbnailSource { file, _ in
            counter.files.append(file)
            return PanelThumbnailsTests.bitmap()
        }
        return (
            PanelThumbnails(
                source: source, budget: PanelThumbnailsTests.thumbnailBytes * pictures),
            counter
        )
    }

    private func file(_ index: Int) -> URL { URL(fileURLWithPath: "/tmp/uttrflow-\(index).png") }

    @Test("forgets the least recently asked for once it is full")
    func evictsTheOldest() async {
        let (thumbnails, counter) = thumbnails(room: 2)

        thumbnails.prepare(file(1))
        await thumbnails.waitForIdle(file: file(1))
        thumbnails.prepare(file(2))
        await thumbnails.waitForIdle(file: file(2))
        thumbnails.prepare(file(3))  // pushes 1 out
        await thumbnails.waitForIdle(file: file(3))
        _ = thumbnails.thumbnail(for: file(2))  // still remembered
        // 1 was forgotten by 3, so reading it kicks off a fresh off-main decode.
        _ = thumbnails.thumbnail(for: file(1))
        await thumbnails.waitForIdle(file: file(1))

        #expect(counter.files == [file(1), file(2), file(3), file(1)])
    }

    /// Recency is about being asked for, not arriving; the top of the panel is looked at on every open.
    @Test("asking again keeps a picture alive")
    func askingRefreshes() async {
        let (thumbnails, counter) = thumbnails(room: 2)

        thumbnails.prepare(file(1))
        await thumbnails.waitForIdle(file: file(1))
        thumbnails.prepare(file(2))
        await thumbnails.waitForIdle(file: file(2))
        _ = thumbnails.thumbnail(for: file(1))  // 1 is now the newer of the two
        thumbnails.prepare(file(3))  // so 2 goes, not 1
        await thumbnails.waitForIdle(file: file(3))
        _ = thumbnails.thumbnail(for: file(1))

        #expect(counter.files == [file(1), file(2), file(3)], "1 was never read twice")
    }

    @Test("holds what it is given, and no more")
    func staysUnderItsBudget() async {
        let room = PanelThumbnailsTests.thumbnailBytes * 3
        let (thumbnails, _) = thumbnails(room: 3)

        for name in 1...20 {
            thumbnails.prepare(file(name))
        }
        for name in 1...20 {
            await thumbnails.waitForIdle(file: file(name))
        }

        #expect(thumbnails.bytesHeld <= room)
        #expect(thumbnails.bytesHeld > 0, "a cache that holds nothing is a decode per frame")
    }

    /// A budget of nothing would forget each answer before it could be used.
    @Test("keeps at least one, whatever it is asked for")
    func neverKeepsNothing() async {
        let (thumbnails, counter) = thumbnails(room: 0)

        thumbnails.prepare(file(1))
        await thumbnails.waitForIdle(file: file(1))
        _ = thumbnails.thumbnail(for: file(1))

        #expect(counter.files == [file(1)])
    }

    /// The bound is the pictures' share of the clipboard budget, spent here because here are the pixels.
    @Test("its bound is the picture tier of the clipboard budget, in bytes")
    func defaultBudget() {
        #expect(PanelThumbnails.defaultBudget == ClipboardBudget.standard.images.bytes)
        #expect(ClipboardBudget.standard.claimed <= ClipboardBudget.standard.ceiling)
    }

    /// The measurement the budget assumes, now that it can be taken.
    @Test("counts and evicts production CGImage-backed thumbnails")
    func cgImageBackedThumbnailHasCost() async throws {
        let url = URL(fileURLWithPath: "/tmp/uttrflow-thumbnail-regression.png")
        let bitmap = PanelThumbnailsTests.bitmap()
        guard let tiff = bitmap.tiffRepresentation,
            let bitmapRep = NSBitmapImageRep(data: tiff),
            let png = bitmapRep.representation(using: .png, properties: [:]),
            let source = CGImageSourceCreateWithData(png as CFData, nil),
            let data = CGImageSourceCreateThumbnailAtIndex(
                source, 0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: PanelThumbnails.maxPixel,
                ] as CFDictionary)
        else {
            Issue.record("could not create a production-style thumbnail")
            return
        }
        let image = NSImage(cgImage: data, size: NSSize(width: data.width, height: data.height))
        #expect(PanelThumbnails.bytes(of: image) > 0)
        let thumbnails = PanelThumbnails(source: PanelThumbnailSource { _, _ in image }, budget: 1)
        thumbnails.prepare(url)
        await thumbnails.waitForIdle(file: url)
        thumbnails.prepare(url.appendingPathExtension("second"))
        await thumbnails.waitForIdle(file: url.appendingPathExtension("second"))
        #expect(thumbnails.bytesHeld > 0)
    }

    @Test("and a thumbnail weighs about what the budget assumed")
    func aThumbnailIsAboutEighteenKilobytes() {
        #expect(PanelThumbnailsTests.thumbnailBytes > 10_000)
        #expect(PanelThumbnailsTests.thumbnailBytes < 30_000)
    }

}
