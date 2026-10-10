// Tests that accepted lines are recorded off the key path and capture work stays bounded.

import Foundation
import Synchronization
import Testing
import UttrflowPredict
import UttrflowPredictCapture
import UttrflowPredictStore

@testable import Uttrflow

/// What the recordings did, in the order they did it.
private final class Journal: Sendable {
    let entries = Mutex<[String]>([])

    func note(_ entry: String) { entries.withLock { $0.append(entry) } }
    var all: [String] { entries.withLock { $0 } }
}

private actor BoundedCaptureSink: CaptureSink {
    private let gate: AsyncStream<Void>
    private let gateContinuation: AsyncStream<Void>.Continuation
    private let started: AsyncStream<Void>
    private let startedContinuation: AsyncStream<Void>.Continuation
    private(set) var recorded: [String] = []
    private var blocksFirstRecord = true

    init() {
        (gate, gateContinuation) = AsyncStream.makeStream(of: Void.self)
        (started, startedContinuation) = AsyncStream.makeStream(of: Void.self)
    }

    func waitUntilBlocked() async {
        var iterator = started.makeAsyncIterator()
        _ = await iterator.next()
    }

    func release() { gateContinuation.yield() }

    func record(
        _ text: String, in surface: Surface, after previous: String?, as origin: LineOrigin, at moment: Date
    ) async throws {
        if blocksFirstRecord {
            blocksFirstRecord = false
            startedContinuation.yield()
            for await _ in gate { break }
        }
        recorded.append(text)
    }

    func supersede(_ text: String, with replacement: String, in surface: Surface) async throws {}
}

@MainActor
@Suite("Recording an accepted suggestion")
struct AcceptanceQueueTests {
    @Test("a recording blocked in the corpus write does not hold the caller, so held keys go first")
    func enqueueReturnsBeforeTheWrite() async {
        let journal = Journal()
        let queue = AcceptanceQueue()
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
        let queuedWhileForgetting = queue.enqueue({})
        #expect(!queuedWhileForgetting, "an acceptance must not be queued after forgetting begins")

        open.yield()
        await forgetting.value
        queue.finishForgetting()
        let queuedAfterForgetting = queue.enqueue({})
        #expect(queuedAfterForgetting, "admission resumes once forgetting has finished")
        await queue.drained()
    }

    @Test("capture overflow abandons queued text until an empty field baseline returns")
    func overflowFailsClosedAndRecoversFromFreshBaseline() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "acceptance-queue-overflow-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let sink = BoundedCaptureSink()
        let preferences = CapturePreferencesFile(path: directory.appending(path: "consent.json").path)
        let capture = CaptureSession(sink: sink, preferencesFile: preferences)
        try await capture.record(.allowed, for: "com.example.editor")
        let queue = AcceptanceQueue { await capture.abandonFocusedField() }
        let reading = FieldReading(bundleIdentifier: "com.example.editor", role: "AXTextField")
        let moment = Date()

        #expect(
            queue.enqueueCapture(
                [.keystroke("completed before overflow", at: moment), .returnPressed(at: moment)],
                in: reading, using: capture))
        await sink.waitUntilBlocked()

        var accepted = 0
        while queue.enqueueCapture(
            [.keystroke("stale partial \(accepted)", at: moment)], in: reading, using: capture)
        {
            accepted += 1
        }
        #expect(accepted == AcceptanceQueue.maximumPendingWrites - 1)
        #expect(
            !queue.enqueueCapture(
                [.keystroke("stale partial after overflow", at: moment), .returnPressed(at: moment)],
                in: reading, using: capture))

        await sink.release()
        await queue.drained()
        let beforeRecovery = await sink.recorded
        #expect(beforeRecovery == ["completed before overflow"])
        #expect(
            !queue.enqueueCapture(
                [.keystroke("stale partial", at: moment), .returnPressed(at: moment)],
                in: reading, using: capture),
            "a non-empty field cannot establish a trustworthy post-overflow baseline")

        #expect(
            queue.enqueueCapture(
                [
                    .keystroke("", at: moment),
                    .typed("fresh", at: moment),
                    .keystroke("fresh", at: moment),
                    .typed(" complete", at: moment),
                    .keystroke("fresh complete", at: moment),
                    .returnPressed(at: moment),
                ], in: reading, using: capture))
        await queue.drained()
        let afterRecovery = await sink.recorded
        #expect(afterRecovery == ["completed before overflow", "fresh complete"])
    }

    @Test("forget waits for the overflow reset barrier before reopening admission")
    func forgetWaitsForOverflowReset() async {
        let journal = Journal()
        let queue = AcceptanceQueue { journal.note("overflow reset") }
        let (gate, open) = AsyncStream<Void>.makeStream()
        #expect(
            queue.enqueue {
                for await _ in gate { break }
            })

        var accepted = 0
        while queue.enqueue({}) { accepted += 1 }
        #expect(accepted == AcceptanceQueue.maximumPendingWrites - 1)

        let forgetting = Task {
            await queue.beginForgetting()
            journal.note("forget ready")
        }
        let admittedWhileForgetting = queue.enqueue({})
        #expect(!admittedWhileForgetting, "forget must keep admission closed behind overflow")
        open.yield()
        await forgetting.value
        #expect(journal.all == ["overflow reset", "forget ready"])
        queue.finishForgetting()
        let admittedAfterForgetting = queue.enqueue({})
        #expect(admittedAfterForgetting, "admission reopens only after the forget operation")
        await queue.drained()
    }

    @Test("a single oversized capture batch also trips the write-byte limit")
    func oversizedCaptureBatchIsRejected() async {
        let journal = Journal()
        let queue = AcceptanceQueue { journal.note("overflow reset") }
        let reading = FieldReading(bundleIdentifier: "com.example.editor", role: "AXTextField")
        let oversized = String(repeating: "x", count: AcceptanceQueue.maximumWriteBytes)

        let bytes = AcceptanceQueue.estimatedBytes(
            for: [.keystroke(oversized, at: Date())], reading: reading)
        #expect(bytes > AcceptanceQueue.maximumWriteBytes)
        let admitted = queue.enqueue({}, estimatedBytes: bytes)
        #expect(!admitted)
        await queue.drained()
        #expect(journal.all == ["overflow reset"])
    }

    @Test("aggregate queued bytes stay below the shared budget")
    func aggregateWriteBudgetIsEnforced() async {
        let queue = AcceptanceQueue()
        var accepted = 0
        while queue.enqueue({}, estimatedBytes: AcceptanceQueue.maximumWriteBytes) {
            accepted += 1
        }
        #expect(accepted == AcceptanceQueue.maximumPendingBytes / AcceptanceQueue.maximumWriteBytes)
        await queue.drained()
    }

    @Test("large surface locator and scope count toward the aggregate byte budget")
    func largeSurfaceMetadataTripsAggregateBudget() async {
        let journal = Journal()
        let queue = AcceptanceQueue { journal.note("overflow reset") }
        let surface = Surface(
            bundleIdentifier: "com.example.editor", role: "AXTextField",
            locator: String(repeating: "l", count: 28 * 1_024),
            scope: String(repeating: "s", count: 28 * 1_024))
        let bytes = AcceptanceQueue.estimatedBytes(for: ["accepted line"], surface: surface)
        #expect(bytes <= AcceptanceQueue.maximumWriteBytes)

        var accepted = 0
        while queue.enqueue({ _ = surface.locator }, estimatedBytes: bytes) { accepted += 1 }
        #expect(accepted > 1)
        #expect(accepted < AcceptanceQueue.maximumPendingWrites)
        #expect(accepted * bytes <= AcceptanceQueue.maximumPendingBytes)
        #expect((accepted + 1) * bytes > AcceptanceQueue.maximumPendingBytes)
        await queue.drained()
        #expect(journal.all == ["overflow reset"])
    }
}
