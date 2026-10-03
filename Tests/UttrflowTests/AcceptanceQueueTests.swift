// Tests that an accepted line is recorded off the key path, in order, and before capture hears anything else.

import Synchronization
import Testing

@testable import Uttrflow

/// What the recordings did, in the order they did it.
private final class Journal: Sendable {
    let entries = Mutex<[String]>([])

    func note(_ entry: String) { entries.withLock { $0.append(entry) } }
    var all: [String] { entries.withLock { $0 } }
}

@MainActor
@Suite("Recording an accepted suggestion")
struct AcceptanceQueueTests {
    @Test("a recording blocked in the corpus write does not hold the caller, so held keys go first")
    func enqueueReturnsBeforeTheWrite() async {
        let queue = AcceptanceQueue()
        let journal = Journal()
        let (gate, open) = AsyncStream<Void>.makeStream()
        queue.enqueue {
            for await _ in gate { break }
            journal.note("recorded")
        }
        journal.note("keys released")
        open.yield()
        await queue.drained()
        #expect(journal.all == ["keys released", "recorded"])
    }

    @Test("recordings finish in the order they were queued, and drained waits for all of them")
    func keepsOrder() async {
        let queue = AcceptanceQueue()
        let journal = Journal()
        let (gate, open) = AsyncStream<Void>.makeStream()
        queue.enqueue {
            for await _ in gate { break }
            journal.note("first")
        }
        queue.enqueue { journal.note("second") }
        open.yield()
        await queue.drained()
        #expect(journal.all == ["first", "second"])
    }

    @Test("forget closes admission before draining earlier writes")
    func forgetFencesNewWrites() async {
        let queue = AcceptanceQueue()
        let (gate, open) = AsyncStream<Void>.makeStream()
        #expect(
            queue.enqueue {
                for await _ in gate { break }
            })

        let forgetting = Task { await queue.beginForgetting() }
        var fenceStarted = false
        for _ in 0..<100 {
            if !queue.enqueue({}) {
                fenceStarted = true
                break
            }
            await Task.yield()
        }
        #expect(fenceStarted, "forget must close admission before waiting for the blocked write")
        #expect(!queue.enqueue({}), "an acceptance must not be queued after forgetting begins")

        open.yield()
        await forgetting.value
        queue.finishForgetting()
        #expect(queue.enqueue({}), "admission resumes once forgetting has finished")
        await queue.drained()
    }
}
