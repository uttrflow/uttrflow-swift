// Tests that matching an announced picture reads it once, bounded, and outside the announcement lock (#1502).

import Foundation
import Testing

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
    func bumpChangeCount() { lock.withLock { count += 1 } }
    func unblock() { lock.withLock { isBlocked = false } }
    /// Lets every reader parked in `image()` return.
    func release() { gate.signal() }

    func text() -> String? { nil }
    func html() -> String? { nil }
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

/// Whether the semaphore is signalled in time, waited on synchronously so the test cannot hang.
private func signalled(_ semaphore: DispatchSemaphore, within seconds: Double) -> Bool {
    semaphore.wait(timeout: .now() + seconds) == .success
}

@Suite("Matching an announced picture", .serialized)
struct AnnouncedPictureReadTests {
    @Test("announcing a write returns promptly while a tick is reading a picture to match")
    func announcingIsNotHeldByAPictureRead() async {
        let source = BlockingPictureSource()
        let watcher = PasteboardWatcher(source: source, readLimit: .seconds(60))
        watcher.ignoreNextPicture(Data([0x89, 0x50, 0x4E, 0x47]))
        source.bumpChangeCount()

        let tick = Task { await watcher.newClip(at: Date()) }
        #expect(signalled(source.entered, within: 30))

        let announced = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            watcher.ignoreNextWrite(of: "pasted by Uttrflow")
            announced.signal()
        }
        #expect(signalled(announced, within: 20), "the paste waited on the picture read")

        source.release()
        _ = await tick.value
    }

    @Test("a picture that is not the announced one is read once and still noticed")
    func aFailedClaimReusesTheRead() async {
        let source = BlockingPictureSource()
        source.unblock()
        let watcher = PasteboardWatcher(source: source)
        watcher.ignoreNextPicture(Data([0x89, 0x50, 0x4E, 0x47]))
        source.bumpChangeCount()

        #expect(await watcher.newClip(at: Date())?.clip.kind == .image)
        #expect(source.reads == 1)
    }

    @Test("a picture read that passes the limit skips the copy")
    func aSlowPictureReadIsGivenUpOn() async {
        let source = BlockingPictureSource()
        let watcher = PasteboardWatcher(source: source, readLimit: .milliseconds(100))
        watcher.ignoreNextPicture(Data([0x89, 0x50, 0x4E, 0x47]))
        source.bumpChangeCount()

        #expect(await watcher.newClip(at: Date()) == nil)
        source.release()
    }
}
