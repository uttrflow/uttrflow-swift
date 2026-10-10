// Tests that matching an announced picture reads it once, bounded, and outside the announcement lock (#1502).

import Foundation
import Dispatch
import Synchronization
import Testing
import UttrflowCore

@testable import UttrflowClipboard

/// A textless clipboard whose `image()` blocks until released and counts how often it is asked.
private final class BlockingPictureSource: ClipboardSource, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 1
    private var isBlocked = true
    private var imageReads = 0
    private let gate = DispatchSemaphore(value: 0)
    let entered = DispatchSemaphore(value: 0)

    var reads: Int { lock.withLock { imageReads } }
    func changeCount() -> Int { lock.withLock { count } }
    @discardableResult
    func bumpChangeCount() -> Int {
        lock.withLock {
            count += 1; return count
        }
    }
    func unblock() { lock.withLock { isBlocked = false } }
    /// Lets every reader parked in `image()` return.
    func release() { gate.signal() }

    func text() -> String? { nil }
    func html() -> String? { nil }
    func hasPicture() -> Bool { true }
    func markers() -> PasteboardMarkers { PasteboardMarkers() }
    func image() -> (data: Data, width: Int, height: Int)? {
        let blocked = lock.withLock {
            imageReads += 1
            return isBlocked
        }
        if blocked {
            entered.signal()
            gate.wait()
            gate.signal()
        }
        return (data: Data([0x47, 0x49, 0x46]), width: 1, height: 1)
    }
    func frontmostApplicationName() -> String? { nil }
}

/// Text reads can be held past the watcher's deadline without blocking the test task.
private final class BlockingTextSource: ClipboardSource, @unchecked Sendable {
    private struct State {
        var count = 0
        var text: String?
        var blocksNextRead = true
    }

    private let state = Mutex(State())
    private let readGate = DispatchSemaphore(value: 0)
    let entered = DispatchSemaphore(value: 0)

    @discardableResult
    func write(_ text: String) -> Int {
        state.withLock {
            $0.count += 1
            $0.text = text
            return $0.count
        }
    }

    func releaseRead() { readGate.signal() }
    func changeCount() -> Int { state.withLock(\.count) }
    func text() -> String? {
        let (text, blocks) = state.withLock { value -> (String?, Bool) in
            let blocks = value.blocksNextRead
            value.blocksNextRead = false
            return (value.text, blocks)
        }
        if blocks {
            entered.signal()
            readGate.wait()
        }
        return text
    }
    func html() -> String? { nil }
    func markers() -> PasteboardMarkers { [] }
    func image() -> (data: Data, width: Int, height: Int)? { nil }
    func frontmostApplicationName() -> String? { nil }
}

/// Whether the semaphore is signalled in time, waited on a thread of its own so no cooperative thread is held.
private func signalled(_ semaphore: DispatchSemaphore, within seconds: Double) async -> Bool {
    await withCheckedContinuation { continuation in
        Thread.detachNewThread {
            continuation.resume(returning: semaphore.wait(timeout: .now() + seconds) == .success)
        }
    }
}

@Suite("Matching an announced picture", .serialized)
struct AnnouncedPictureReadTests {
    @Test("announcing a write returns promptly while a tick is reading a picture to match")
    func announcingIsNotHeldByAPictureRead() async {
        let source = BlockingPictureSource()
        let watcher = PasteboardWatcher(source: source, readLimit: .seconds(60))
        let finishWrite = watcher.ignoreNextPicture(Data([0x89, 0x50, 0x4E, 0x47]))
        finishWrite(source.bumpChangeCount())

        let tickResult = Mutex("still running")
        let tick = Task {
            let result = await watcher.newClip(at: Date())
            tickResult.withLock { $0 = String(describing: result) }
            return result
        }
        let reachedPictureSource = await signalled(source.entered, within: 30)
        if !reachedPictureSource {
            let observed = tickResult.withLock { $0 }
            let completion = observed == "still running" ? "still running after 30s" : observed
            source.release()
            _ = await tick.value
            #expect(
                reachedPictureSource,
                "picture source was not entered within 30s; watcher tick was \(completion)"
            )
            return
        }

        let announced = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            watcher.ignoreNextWrite(of: "pasted by Uttrflow")
            announced.signal()
        }
        #expect(await signalled(announced, within: 20), "the paste waited on the picture read")

        source.release()
        _ = await tick.value
    }

    @Test("a picture that is not the announced one is read once and still noticed")
    func aFailedClaimReusesTheRead() async {
        let source = BlockingPictureSource()
        source.unblock()
        let watcher = PasteboardWatcher(source: source)
        let finishWrite = watcher.ignoreNextPicture(Data([0x89, 0x50, 0x4E, 0x47]))
        finishWrite(source.bumpChangeCount())

        #expect(await watcher.newClip(at: Date())?.clip.kind == .image)
        #expect(source.reads == 1)
    }

    @Test("a picture read that passes the limit skips the copy")
    func aSlowPictureReadIsGivenUpOn() async {
        let source = BlockingPictureSource()
        let watcher = PasteboardWatcher(source: source, readLimit: .milliseconds(100))
        let finishWrite = watcher.ignoreNextPicture(Data([0x89, 0x50, 0x4E, 0x47]))
        finishWrite(source.bumpChangeCount())

        #expect(await watcher.newClip(at: Date()) == nil)
        source.release()
    }

    @Test("a timed out text read withdraws an announcement before the next same-text copy")
    func timedOutReadWithdrawsAnnouncement() async {
        let source = BlockingTextSource()
        let watcher = PasteboardWatcher(source: source, readLimit: .milliseconds(100))
        let finishWrite = watcher.ignoreNextWrite(of: "same words")
        finishWrite(source.write("same words"))

        let tick = Task { await watcher.newClip(at: Date()) }
        #expect(await signalled(source.entered, within: 5))
        #expect(await tick.value == nil)

        source.releaseRead()
        source.write("same words")
        #expect(await watcher.newClip(at: Date())?.clip.text == "same words")
    }
}
