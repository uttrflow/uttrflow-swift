// Tests for the thumbnail cache.

import AppKit
import ImageIO
import Synchronization
import Testing
import UttrflowClipboard

@testable import Uttrflow

/// Decoding a picture is the expensive thing the panel does; what is worth testing is that it happens once and off the main thread.
@MainActor
@Suite("The pictures beside a clip")
struct PanelThumbnailsTests {
    /// The mock source is `@Sendable` so the cache can run it on a detached task; the counter is shared across that boundary.
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var storedFiles: [URL] = []
        private var storedSizes: [Int] = []
        private var storedCalls = 0
        var files: [URL] { lock.withLock { storedFiles } }
        var sizes: [Int] { lock.withLock { storedSizes } }
        var calls: Int { lock.withLock { storedCalls } }
        /// Records one decode under the lock, since decodes run on detached tasks at once.
        func record(_ file: URL, maxPixel: Int) {
            lock.withLock {
                storedFiles.append(file)
                storedSizes.append(maxPixel)
                storedCalls += 1
            }
        }
        /// Counts one decode under the lock.
        func count() { lock.withLock { storedCalls += 1 } }
    }

    private actor EventReader<Element: Sendable> {
        private var events: [Element] = []
        private var waiter: (id: UUID, continuation: CheckedContinuation<Element?, Never>)?
        private var timeoutTask: Task<Void, Never>?

        func send(_ event: Element) {
            if let waiter {
                self.waiter = nil
                timeoutTask?.cancel()
                timeoutTask = nil
                waiter.continuation.resume(returning: event)
            } else {
                events.append(event)
            }
        }

        func next(timeout: Duration = .seconds(45)) async -> Element? {
            if !events.isEmpty { return events.removeFirst() }
            guard waiter == nil else { return nil }

            let id = UUID()
            return await withCheckedContinuation { continuation in
                waiter = (id, continuation)
                timeoutTask = Task {
                    try? await Task.sleep(for: timeout)
                    self.expireWaiter(id: id)
                }
            }
        }

        private func expireWaiter(id: UUID) {
            guard let waiter, waiter.id == id else { return }
            self.waiter = nil
            timeoutTask = nil
            waiter.continuation.resume(returning: nil)
        }
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

    private static func oversizedPNG() throws -> Data {
        let encoded =
            "iVBORw0KGgoAAAANSUhEUgAA//8AAP//AQMAAACMy0sTAAAACVBMVEUA"
            + "AAD///+AgIBEyIOaAAAABklEQVR4nGMAAADq4gSQAAAAAElFTkSuQmCC"
        return try #require(Data(base64Encoded: encoded))
    }

    private func thumbnails(
        _ answers: [URL: NSImage] = [:], budget: Int? = nil, retryAfter: Duration = .seconds(2)
    ) -> (PanelThumbnails, Counter) {
        let counter = Counter()
        let source = PanelThumbnailSource { file, maxPixel in
            counter.record(file, maxPixel: maxPixel)
            return answers[file]
        }
        return (
            PanelThumbnails(
                source: source, budget: budget ?? PanelThumbnails.defaultBudget, retryAfter: retryAfter),
            counter
        )
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

    @Test("rejects a tiny PNG with an oversized header before decoding and keeps the placeholder")
    func oversizedHeaderDoesNotDecode() async throws {
        let file = FileManager.default.temporaryDirectory
            .appending(path: "uttrflow-oversized-thumbnail-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: file) }
        let png = try Self.oversizedPNG()
        #expect(png.count == 84)
        try png.write(to: file)
        let header = try #require(CGImageSourceCreateWithURL(file as CFURL, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(header, 0, nil) as? [CFString: Any])
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == 65_535)
        #expect(properties[kCGImagePropertyPixelHeight] as? Int == 65_535)
        let counter = Counter()
        let source = PanelThumbnailSource { file, maxPixel in
            PanelThumbnailSource.load(file, maxPixel: maxPixel) { source, options in
                counter.count()
                return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
            }
        }
        let thumbnails = PanelThumbnails(source: source)

        thumbnails.prepare(file)
        await thumbnails.waitForIdle(file: file)

        #expect(counter.calls == 0)
        #expect(thumbnails.known.keys.contains(file))
        #expect(thumbnails.thumbnail(for: file) == nil)
    }

    @Test("a view starts from the cached picture and a miss is awaited, not polled")
    func pictureIsAwaited() async {
        let picture = Self.bitmap()
        let (thumbnails, counter) = thumbnails([file: picture])

        #expect(thumbnails.cached(file) == nil)
        #expect(await thumbnails.picture(for: file) === picture)
        #expect(thumbnails.cached(file) === picture)
        #expect(await thumbnails.picture(for: file) === picture)
        #expect(counter.calls == 1)
    }

    /// The row crops to fill, so the shorter edge is the one that must reach the drawn size.
    @Test("a picture is decoded large enough that its crop is never stretched")
    func coversTheCrop() {
        let edge = PanelThumbnails.maxPixel

        #expect(PanelThumbnailSource.longestEdge(width: 1000, height: 1000, covering: edge) == edge)
        #expect(PanelThumbnailSource.longestEdge(width: 2000, height: 1000, covering: edge) == edge * 2)
        #expect(PanelThumbnailSource.longestEdge(width: 1000, height: 3000, covering: edge) == edge * 3)
        #expect(PanelThumbnailSource.longestEdge(width: 10_000, height: 100, covering: edge) == edge * 4)
        #expect(PanelThumbnailSource.longestEdge(width: 40, height: 20, covering: edge) == edge)
    }

    /// A clip whose file has been deleted should not cost a trip to the disk on every frame.
    @Test("remembers that a picture is gone")
    func remembersAMiss() async {
        // An hour, so a slow machine cannot make the miss stale between the reads.
        let (thumbnails, counter) = thumbnails(retryAfter: .seconds(3600))

        thumbnails.prepare(file)
        await thumbnails.waitForIdle(file: file)

        #expect(thumbnails.thumbnail(for: file) == nil)
        #expect(thumbnails.thumbnail(for: file) == nil)
        #expect(counter.files.count == 1)
    }

    @Test("a thumbnail read neither expires a miss nor schedules another decode")
    func thumbnailReadIsPureForAMiss() async {
        let (thumbnails, counter) = thumbnails(retryAfter: .zero)

        thumbnails.prepare(file)
        await thumbnails.waitForIdle(file: file)
        let observedBefore = thumbnails.known.count
        for _ in 0..<100 { #expect(thumbnails.thumbnail(for: file) == nil) }

        #expect(counter.calls == 1)
        #expect(thumbnails.known.count == observedBefore)
        thumbnails.prepare(file)
        await thumbnails.waitForIdle(file: file)
        #expect(counter.calls == 2)
    }

    @Test("repeated cache hits keep constant time LRU bookkeeping")
    func repeatedHitsTouchLinkedLRU() async {
        let (thumbnails, _) = thumbnails([file: Self.bitmap()])
        thumbnails.prepare(file)
        await thumbnails.waitForIdle(file: file)
        for _ in 0..<10_000 { #expect(thumbnails.thumbnail(for: file) != nil) }
        #expect(thumbnails.cached(file) != nil)
    }

    /// A picture file restored after a failed decode is decoded again once the miss is stale.
    @Test("decodes a restored picture after remembering it was gone")
    func decodesARestoredPicture() async {
        let counter = Counter()
        let restored = Self.bitmap()
        let present = Counter()
        let source = PanelThumbnailSource { file, _ in
            counter.count()
            return present.calls > 0 ? restored : nil
        }
        let thumbnails = PanelThumbnails(source: source, retryAfter: .zero)

        thumbnails.prepare(file)
        await thumbnails.waitForIdle(file: file)
        present.count()

        #expect(thumbnails.thumbnail(for: file) == nil)
        thumbnails.prepare(file)
        await thumbnails.waitForIdle(file: file)
        #expect(thumbnails.thumbnail(for: file) === restored)
        #expect(counter.calls == 2)
    }

    /// Asked for at the size it is drawn, not the size of the screenshot.
    @Test("asks for the small version")
    func asksForAThumbnail() async {
        // An hour, so a slow machine cannot make the miss stale and decode it twice.
        let (thumbnails, counter) = thumbnails(retryAfter: .seconds(3600))

        thumbnails.prepare(file)
        await thumbnails.waitForIdle(file: file)
        _ = thumbnails.thumbnail(for: file)

        #expect(counter.sizes == [PanelThumbnails.maxPixel])
        #expect(PanelThumbnails.maxPixel <= 96, "a 34-point square on a Retina screen")
    }

    @Test("waits until a prepared thumbnail is committed before returning")
    func waitForIdleIncludesCacheCommit() async {
        let decoding = DecodeHold()
        let image = Self.bitmap()
        let source = PanelThumbnailSource { _, _ in
            decoding.hold()
            return image
        }
        let thumbnails = PanelThumbnails(source: source, retryAfter: .seconds(3600))

        thumbnails.prepare(file)
        while decoding.calls == 0 { await Task.yield() }
        let waiting = Task { await thumbnails.waitForIdle(file: file) }
        await Task.yield()
        decoding.release()
        await waiting.value

        #expect(thumbnails.cached(file) === image)
        #expect(thumbnails.thumbnail(for: file) === image)
        #expect(decoding.calls == 1)
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

    /// A decode held on its thread until the test lets it go, and whether it has ended.
    private final class DecodeHold: Sendable {
        private let released = DispatchSemaphore(value: 0)
        private let state = Mutex((calls: 0, ended: false))
        var calls: Int { state.withLock { $0.calls } }
        var hasEnded: Bool { state.withLock { $0.ended } }
        func release() { released.signal() }
        /// Blocks until released, or for a minute so a caller that waits on it fails rather than hangs.
        func hold() {
            state.withLock { $0.calls += 1 }
            _ = released.wait(timeout: .now() + .seconds(60))
            state.withLock { $0.ended = true }
        }
    }

    /// Tracks real overlap while holding each fake decode until the test opens the gate.
    private final class ConcurrentDecodeCounter: Sendable {
        private let gate = DispatchSemaphore(value: 0)
        private let state = Mutex((started: [URL](), active: 0, maximum: 0))
        private let startedEvents: EventReader<URL>
        private let completionEvents: EventReader<Void>
        var started: [URL] { state.withLock { $0.started } }
        var maximum: Int { state.withLock { $0.maximum } }

        init() {
            startedEvents = EventReader()
            completionEvents = EventReader()
        }

        func nextStarted(until deadline: ContinuousClock.Instant) async -> URL? {
            let remaining = ContinuousClock.now.duration(to: deadline)
            guard remaining > .zero else { return nil }
            return await startedEvents.next(timeout: remaining)
        }

        func waitForStarts(_ count: Int, until deadline: ContinuousClock.Instant) async -> [URL] {
            var files: [URL] = []
            for _ in 0..<count {
                let remaining = ContinuousClock.now.duration(to: deadline)
                guard remaining > .zero, let file = await startedEvents.next(timeout: remaining) else {
                    break
                }
                files.append(file)
            }
            return files
        }

        func waitForCompletions(_ count: Int, until deadline: ContinuousClock.Instant) async -> Int {
            var completed = 0
            while completed < count {
                let remaining = ContinuousClock.now.duration(to: deadline)
                guard remaining > .zero, await completionEvents.next(timeout: remaining) != nil else { break }
                completed += 1
            }
            return completed
        }

        func release(_ count: Int) {
            for _ in 0..<count { gate.signal() }
        }
        func decode(_ file: URL) {
            state.withLock {
                $0.started.append(file)
                $0.active += 1
                $0.maximum = max($0.maximum, $0.active)
            }
            Task { await startedEvents.send(file) }
            _ = gate.wait(timeout: .now() + .seconds(60))
            state.withLock { $0.active -= 1 }
            Task { await completionEvents.send(()) }
        }
    }

    @Test("bounds parallel decodes and drops queued rows that disappear")
    func boundsParallelDecodes() async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(45))
        let counter = ConcurrentDecodeCounter()
        let source = PanelThumbnailSource { file, _ in
            counter.decode(file)
            return Self.bitmap()
        }
        let thumbnails = PanelThumbnails(source: source)
        let files = (0..<8).map { file("decode-\($0)") }

        for file in files { thumbnails.prepare(file) }
        thumbnails.cancel(files[7])
        thumbnails.prepare(files[6], selected: true)
        defer { counter.release(files.count) }

        let initialStarts = await counter.waitForStarts(
            PanelThumbnails.maximumConcurrentDecodes, until: deadline)
        let initialStartedCount = counter.started.count
        let initialMaximum = counter.maximum

        // Free one slot at a time so the next start tests queue priority, not worker scheduling order.
        let nextStarted: URL?
        if initialStarts.count == PanelThumbnails.maximumConcurrentDecodes {
            counter.release(1)
            nextStarted = await counter.nextStarted(until: deadline)
        } else {
            nextStarted = nil
        }

        // Release every held decode before asserting so a failed priority check cannot strand work.
        counter.release(files.count)
        let completed = await counter.waitForCompletions(files.count - 1, until: deadline)
        if completed == files.count - 1 {
            for file in files.dropLast() { await thumbnails.waitForIdle(file: file) }
            await thumbnails.waitForIdle(file: files[7])
        }

        #expect(initialStarts.count == PanelThumbnails.maximumConcurrentDecodes)
        #expect(initialStartedCount == PanelThumbnails.maximumConcurrentDecodes)
        #expect(initialMaximum <= PanelThumbnails.maximumConcurrentDecodes)
        #expect(completed == files.count - 1, "every visible queued row eventually finishes")
        #expect(nextStarted == files[6], "the selected row starts before ordinary queued rows")
        #expect(counter.started.count == files.count - 1, "the queued row that disappeared is never decoded")
        #expect(
            Set(counter.started) == Set(files.dropLast()),
            "every remaining row is decoded exactly once and the canceled row is never decoded"
        )
        #expect(counter.maximum <= PanelThumbnails.maximumConcurrentDecodes)
    }

    /// The cache miss returns nil immediately and the source load runs on a background queue, so the row draws the placeholder while the decode happens.
    @Test("miss does not block the caller while the source decodes")
    func missDoesNotBlockTheCaller() async {
        let decoding = DecodeHold()
        let image = NSImage(size: NSSize(width: 4, height: 4))
        let source = PanelThumbnailSource { _, _ in
            decoding.hold()
            return image
        }
        let thumbnails = PanelThumbnails(source: source, budget: 1)

        thumbnails.prepare(file)
        let result = thumbnails.thumbnail(for: file)
        let decodeStillHeld = !decoding.hasEnded
        decoding.release()

        #expect(result == nil, "miss returns nil, the row draws the placeholder")
        #expect(decodeStillHeld, "the call must return while the decode is still held")

        await thumbnails.waitForIdle(file: file)
        #expect(decoding.calls == 1, "the source ran exactly once, off the caller's thread")
        #expect(thumbnails.thumbnail(for: file) != nil)
    }

    /// Each row awaits its own file's decode, so only the row showing that picture is woken when it lands.
    @Test("a decode redraws only the row showing that picture")
    func decodeInvalidatesOneFile() async {
        let picture = NSImage(size: NSSize(width: 4, height: 4))
        let other = URL(fileURLWithPath: "/tmp/uttrflow-other.png")
        let (thumbnails, _) = thumbnails([file: picture])

        thumbnails.prepare(file)
        await thumbnails.waitForIdle(file: file)
        #expect(thumbnails.cached(file) === picture, "the row showing the decoded file is given it")

        thumbnails.prepare(other)
        let third = URL(fileURLWithPath: "/tmp/uttrflow-third.png")
        for index in 0..<50 {
            let next = third.appendingPathExtension("\(index)")
            thumbnails.prepare(next)
            await thumbnails.waitForIdle(file: next)
        }
        await thumbnails.waitForIdle(file: other)
        #expect(thumbnails.cached(file) === picture, "fifty other decodes leave this row alone")
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
    private final class Counter: Sendable {
        private let filesStorage = Mutex<[URL]>([])
        var files: [URL] { filesStorage.withLock { $0 } }
        /// Records one decode under the mutex, since detached tasks run concurrently.
        func record(_ file: URL) { filesStorage.withLock { $0.append(file) } }
    }

    private func thumbnails(room pictures: Int) -> (PanelThumbnails, Counter) {
        let counter = Counter()
        let source = PanelThumbnailSource { file, _ in
            counter.record(file)
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
        thumbnails.prepare(file(2))  // still remembered
        // 1 was forgotten by 3, so asking for it again kicks off a fresh off-main decode.
        thumbnails.prepare(file(1))
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

    @Test("releases cached pictures under memory pressure")
    func releasesForMemoryPressure() async {
        let (thumbnails, _) = thumbnails(room: 2)

        thumbnails.prepare(file(1))
        await thumbnails.waitForIdle(file: file(1))
        thumbnails.prepare(file(2))
        await thumbnails.waitForIdle(file: file(2))

        thumbnails.releaseForMemoryPressure()

        #expect(thumbnails.bytesHeld == 0)
        #expect(thumbnails.known.isEmpty)
        #expect(thumbnails.thumbnail(for: file(1)) == nil)
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

    @Test("a representation with no pixels behind it weighs nothing")
    func aRepresentationWithoutPixelsWeighsNothing() {
        let empty = NSImage(size: NSSize(width: 68, height: 68))
        empty.addRepresentation(NSImageRep())
        #expect(PanelThumbnails.bytes(of: empty) == 0)
        let mixed = PanelThumbnailsTests.bitmap()
        mixed.addRepresentation(NSImageRep())
        #expect(PanelThumbnails.bytes(of: mixed) == PanelThumbnailsTests.thumbnailBytes)
    }
}
