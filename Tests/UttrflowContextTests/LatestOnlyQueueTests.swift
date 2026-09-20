// Tests that a read nobody waits for any more does not delay the next one (#888).

import Foundation
import Testing

@testable import UttrflowContext

@Suite("The queue that runs only the newest read")
struct LatestOnlyQueueTests {
    @Test("a read queued behind a stall is skipped, so the newest one is answered within its allowance")
    func aStalledReadDoesNotDelayTheNewest() async throws {
        let queue = LatestOnlyQueue(label: "test.latest-only", qos: .userInitiated)
        let ran = Counter()

        // The stall: it holds the queue for well past every allowance below.
        async let stalled = queue.run(within: .milliseconds(100)) { _ -> Int? in
            Thread.sleep(forTimeInterval: 1.5)
            return 0
        }
        try await Task.sleep(for: .milliseconds(50))

        // Three reads queue behind it; only the last is still wanted when the stall ends.
        async let first = queue.run(within: .seconds(5)) { _ -> Int? in
            ran.bump()
            return 1
        }
        try await Task.sleep(for: .milliseconds(10))
        async let second = queue.run(within: .seconds(5)) { _ -> Int? in
            ran.bump()
            return 2
        }
        try await Task.sleep(for: .milliseconds(10))
        let started = ContinuousClock().now
        let newest = await queue.run(within: .seconds(5)) { _ -> Int? in
            ran.bump()
            return 3
        }
        let took = ContinuousClock().now - started

        #expect(await stalled == nil, "the stall passed its allowance")
        #expect(await first == nil)
        #expect(await second == nil)
        #expect(newest == 3)
        #expect(ran.count == 1, "the skipped reads sent nothing")
        #expect(took < .seconds(3), "\(took)")
    }

    @Test("a read is told it is no longer wanted once a newer one arrives")
    func workIsToldWhenItIsDropped() async {
        let queue = LatestOnlyQueue(label: "test.latest-only-wanted", qos: .userInitiated)
        let wanted = Flag()

        async let slow = queue.run(within: .seconds(5)) { isWanted -> Int? in
            Thread.sleep(forTimeInterval: 0.2)
            wanted.set(isWanted())
            return 1
        }
        try? await Task.sleep(for: .milliseconds(50))
        _ = await queue.run(within: .seconds(5)) { _ -> Int? in 2 }
        _ = await slow

        #expect(wanted.value == false)
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
