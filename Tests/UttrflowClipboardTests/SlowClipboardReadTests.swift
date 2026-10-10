// Tests that a clipboard read another process has to answer cannot hold up the watcher (#895).

import Foundation
import Synchronization
import Testing
import UttrflowCore

@testable import UttrflowClipboard

/// A source whose `text()` takes longer than the limit, standing in for a promised or remote copy.
private final class SlowSource: ClipboardSource, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 1
    private var isSlow = true

    func changeCount() -> Int { lock.withLock { count } }
    func bumpChangeCount() { lock.withLock { count += 1 } }
    func deliverPromptly() { lock.withLock { isSlow = false } }

    func text() -> String? {
        if lock.withLock({ isSlow }) {
            Thread.sleep(forTimeInterval: 5)
        }
        return "delivered at last"
    }

    func html() -> String? { nil }
    func markers() -> PasteboardMarkers { PasteboardMarkers() }
    func image() -> (data: Data, width: Int, height: Int)? { nil }
    func frontmostApplicationName() -> String? { nil }
}

@Suite("A clipboard read the writing app has not answered", .serialized)
struct SlowClipboardReadTests {
    @Test("the read is given up on, and the next copy is still noticed")
    func aSlowReadIsGivenUpOn() async {
        let source = SlowSource()
        let watcher = PasteboardWatcher(
            source: source, interval: .milliseconds(10), readLimit: .milliseconds(200))
        source.bumpChangeCount()

        // The answer is what is checked, not the clock: a loaded machine can be slow to resume either way.
        let clip = await watcher.newClip(at: Date())

        #expect(clip == nil, "a copy nobody delivered in time is skipped")

        source.deliverPromptly()
        source.bumpChangeCount()
        #expect(await watcher.newClip(at: Date())?.clip.text == "delivered at last")
    }

    @Test("timed-out reads release their slots, and a later healthy copy lands")
    func timedOutReadSlotsAreReleased() async {
        let source = BlockedSource()
        let watcher = PasteboardWatcher(
            source: source, interval: .milliseconds(10), readLimit: .milliseconds(50))

        // Every one of these copies blocks in `text()` and times out from the caller's side.
        for _ in 0..<(PasteboardWatcher.maxOutstandingReads + 3) {
            source.bumpChangeCount()
            let clip = await watcher.newClip(at: Date())
            #expect(clip == nil)
        }
        #expect(await watcher.outstandingReads == 0)

        // Freeing the blocked workers lets them return and give their slots back.
        source.releaseBlocked()
        while await watcher.outstandingReads != 0 { await Task.yield() }

        source.deliverPromptly()
        source.bumpChangeCount()
        #expect(await watcher.newClip(at: Date())?.clip.text == "delivered at last")
    }

    @Test("a clipboard generation is retried after its read times out")
    func timedOutGenerationIsRetried() async {
        let source = BlockedSource()
        let watcher = PasteboardWatcher(
            source: source, interval: .milliseconds(10), readLimit: .milliseconds(50))
        defer { source.releaseBlocked() }
        source.bumpChangeCount()

        #expect(await watcher.newClip(at: Date()) == nil)

        source.deliverPromptly()
        #expect(await watcher.newClip(at: Date())?.clip.text == "delivered at last")
    }

    @Test("capture resumes while earlier timed-out reads remain blocked")
    func captureResumesWithBlockedWorkers() async {
        let source = BlockedSource()
        let watcher = PasteboardWatcher(
            source: source, interval: .milliseconds(10), readLimit: .milliseconds(50))
        defer {
            for _ in 0..<PasteboardWatcher.maxOutstandingReads { source.releaseBlocked() }
        }

        for _ in 0..<PasteboardWatcher.maxOutstandingReads {
            source.bumpChangeCount()
            #expect(await watcher.newClip(at: Date()) == nil)
        }

        source.deliverPromptly()
        source.bumpChangeCount()
        #expect(await watcher.newClip(at: Date())?.clip.text == "delivered at last")
    }

    @Test("capture reports repeated timeouts once and retries until a read answers")
    func reportsDegradationOnceWhileRetrying() async {
        let source = RecoveringSource(blockedReads: 2)
        let watcher = PasteboardWatcher(
            source: source, interval: .milliseconds(5), readLimit: .milliseconds(20))
        let (clips, clipContinuation) = AsyncStream.makeStream(of: NoticedClip.self)
        let (degraded, degradedContinuation) = AsyncStream.makeStream(of: Void.self)
        let noticeCount = Mutex(0)
        var startedReads = source.reads.makeAsyncIterator()
        let task = Task {
            await watcher.run(
                handing: { clipContinuation.yield($0) },
                whenCaptureDegrades: {
                    noticeCount.withLock { $0 += 1 }
                    degradedContinuation.yield(())
                })
        }
        defer {
            task.cancel()
            source.releaseBlocked()
        }
        source.bumpChangeCount()

        var degradedEvents = degraded.makeAsyncIterator()
        #expect(await degradedEvents.next() != nil)
        while let read = await startedReads.next(), read < 3 {}
        var noticedClips = clips.makeAsyncIterator()
        #expect(await noticedClips.next()?.clip.text == "delivered at last")
        task.cancel()
        await task.value

        #expect(noticeCount.withLock { $0 } == 1)
    }
}

/// Blocks a fixed number of reads, then answers retries for the same clipboard generation.
private final class RecoveringSource: ClipboardSource, @unchecked Sendable {
    private struct State {
        var count = 1
        var reads = 0
    }

    private let lock = NSLock()
    private var state = State()
    private let blockedReads: Int
    private let gate = DispatchSemaphore(value: 0)
    let reads: AsyncStream<Int>
    private let readContinuation: AsyncStream<Int>.Continuation

    init(blockedReads: Int) {
        self.blockedReads = blockedReads
        (reads, readContinuation) = AsyncStream.makeStream(of: Int.self)
    }

    func changeCount() -> Int { lock.withLock { state.count } }
    func bumpChangeCount() { lock.withLock { state.count += 1 } }

    func text() -> String? {
        let number = lock.withLock {
            state.reads += 1
            return state.reads
        }
        readContinuation.yield(number)
        if number <= blockedReads { gate.wait() }
        return "delivered at last"
    }

    func releaseBlocked() {
        for _ in 0..<blockedReads { gate.signal() }
        readContinuation.finish()
    }

    func html() -> String? { nil }
    func markers() -> PasteboardMarkers { PasteboardMarkers() }
    func image() -> (data: Data, width: Int, height: Int)? { nil }
    func frontmostApplicationName() -> String? { nil }
}

/// A source whose `text()` blocks until released, so a caller can hold several readers open at once.
private final class BlockedSource: ClipboardSource, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 1
    private var isBlocked = true
    private let gate = DispatchSemaphore(value: 0)

    func changeCount() -> Int { lock.withLock { count } }
    func bumpChangeCount() { lock.withLock { count += 1 } }
    func deliverPromptly() { lock.withLock { isBlocked = false } }
    /// Lets every reader parked in `text()` return.
    func releaseBlocked() { gate.signal() }

    func text() -> String? {
        if lock.withLock({ isBlocked }) {
            gate.wait()
            gate.signal()
        }
        return "delivered at last"
    }

    func html() -> String? { nil }
    func markers() -> PasteboardMarkers { PasteboardMarkers() }
    func image() -> (data: Data, width: Int, height: Int)? { nil }
    func frontmostApplicationName() -> String? { nil }
}
