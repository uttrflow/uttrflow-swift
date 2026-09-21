// Tests that a read nobody waits for any more does not delay the next one (#888).

import Dispatch
import Foundation
import Testing
import UttrflowTestSupport

@testable import UttrflowContext

@Suite("The queue that runs only the newest read", .timeLimit(.minutes(1)))
struct LatestOnlyQueueTests {
    @Test("a read queued behind a stall is skipped, so the newest one is answered within its allowance")
    func aStalledReadDoesNotDelayTheNewest() async throws {
        let queue = LatestOnlyQueue(label: "test.latest-only", qos: .userInitiated)
        let ran = Counter()
        let holding = Signal()
        let letGo = DispatchSemaphore(value: 0)

        // The stall: it holds the queue until every read below has taken its number.
        async let stalled = queue.run(within: .milliseconds(100)) { _ -> Int? in
            holding.fire()
            letGo.wait()
            return 0
        }
        // Waited for rather than slept past: a loaded machine can leave a sleep with nothing queued.
        try await arrival(of: holding.fired)

        // Three reads queue behind it; only the last is still wanted when the stall ends.
        async let first = queue.run(within: .seconds(5)) { _ -> Int? in
            ran.bump()
            return 1
        }
        try await eventually { queue.requested == 2 }
        async let second = queue.run(within: .seconds(5)) { _ -> Int? in
            ran.bump()
            return 2
        }
        try await eventually { queue.requested == 3 }
        async let newest = queue.run(within: .seconds(5)) { _ -> Int? in
            ran.bump()
            return 3
        }
        try await eventually { queue.requested == 4 }

        // The stall is still on the queue, so its allowance is the only thing that can answer it.
        #expect(await stalled == nil, "the stall passed its allowance")
        letGo.signal()

        #expect(await first == nil)
        #expect(await second == nil)
        #expect(await newest == 3, "the newest read was answered rather than left to its deadline")
        #expect(ran.count == 1, "the skipped reads sent nothing")
    }

    @Test("a read is told it is no longer wanted once a newer one arrives")
    func workIsToldWhenItIsDropped() async throws {
        let queue = LatestOnlyQueue(label: "test.latest-only-wanted", qos: .userInitiated)
        let wanted = Flag()
        let running = Signal()
        let told = Signal()
        let newerArrived = DispatchSemaphore(value: 0)

        async let slow = queue.run(within: .seconds(5)) { isWanted -> Int? in
            running.fire()
            newerArrived.wait()
            wanted.set(isWanted())
            told.fire()
            return 1
        }
        // The newer read is only newer once this one is running; a sleep leaves it dropped instead.
        try await arrival(of: running.fired)

        async let newer = queue.run(within: .seconds(5)) { _ -> Int? in 2 }
        // The slow read reads its standing only once the newer one has taken a number, which a sleep cannot promise.
        try await eventually { queue.requested == 2 }
        newerArrived.signal()
        try await arrival(of: told.fired)

        #expect(wanted.value == false)
        _ = await slow
        _ = await newer
    }
}

/// Counts how many reads actually ran.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var runs = 0
    var count: Int { lock.withLock { runs } }
    func bump() { lock.withLock { runs += 1 } }
}

/// What a read was told about still being wanted.
private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag: Bool?
    var value: Bool? { lock.withLock { flag } }
    func set(_ new: Bool) { lock.withLock { flag = new } }
}
