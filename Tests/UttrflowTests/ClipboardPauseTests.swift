import XCTest

@testable import Uttrflow

@MainActor
final class ClipboardPauseTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    func testPausingLastsAnHourAndClearingEndsIt() {
        var clock = start
        let pause = ClipboardPause(now: { clock })
        XCTAssertFalse(pause.isActive)
        XCTAssertEqual(pause.set(true), start.addingTimeInterval(3600))
        XCTAssertTrue(pause.isActive)
        clock = start.addingTimeInterval(3601)
        XCTAssertFalse(pause.isActive)
        pause.set(true)
        XCTAssertNil(pause.set(false))
        XCTAssertFalse(pause.isActive)
    }

    func testLoadAdoptsAStoredDeadline() {
        let pause = ClipboardPause(now: { self.start })
        pause.load(start.addingTimeInterval(60))
        XCTAssertTrue(pause.isActive)
        pause.load(nil)
        XCTAssertFalse(pause.isActive)
    }

    func testTimerExpiresThePauseOnce() async {
        var clock = start
        let pause = ClipboardPause(until: start.addingTimeInterval(5), now: { clock }, sleep: { _ in })
        let expired = expectation(description: "expired")
        pause.startTimerIfNeeded {
            expired.fulfill()
        }
        clock = start.addingTimeInterval(6)
        await fulfillment(of: [expired], timeout: 2)
        XCTAssertNil(pause.until)
    }

    func testClockSteppedBackDuringTheSleepDoesNotEndThePauseEarly() async {
        var clock = start
        let slept = Gate()
        let pause = ClipboardPause(
            until: start.addingTimeInterval(100), now: { clock }, sleep: { _ in await slept.pass() })
        let expired = expectation(description: "expired")
        expired.isInverted = true
        pause.startTimerIfNeeded { expired.fulfill() }
        await slept.waitUntilEntered(1)
        // The sleep returns while the clock still shows the deadline ahead, as after a backward step.
        clock = start.addingTimeInterval(-3600)
        await slept.release()
        await slept.waitUntilEntered(2)
        await fulfillment(of: [expired], timeout: 0.2)
        XCTAssertNotNil(pause.until)
        pause.cancelTimer()
        await slept.release()
    }

    func testCancelledTimerNeverFires() async {
        var clock = start
        let gate = Gate()
        let pause = ClipboardPause(
            until: start.addingTimeInterval(5), now: { clock }, sleep: { _ in await gate.pass() })
        let expired = expectation(description: "expired")
        expired.isInverted = true
        pause.startTimerIfNeeded { expired.fulfill() }
        await gate.waitUntilEntered(1)
        pause.set(false)
        // Without the cancel, the released sleeper would reach `onExpiry` once the deadline has passed.
        clock = start.addingTimeInterval(10)
        await gate.release()
        await fulfillment(of: [expired], timeout: 0.3)
    }

    func testNoTimerWithoutAPause() async {
        let pause = ClipboardPause(now: { self.start }, sleep: { _ in })
        let expired = expectation(description: "expired")
        expired.isInverted = true
        pause.startTimerIfNeeded { expired.fulfill() }
        await fulfillment(of: [expired], timeout: 0.3)
    }
}

/// A sleeper the test controls: it parks each caller until `release`, ignoring cancellation.
private actor Gate {
    private var parked: [CheckedContinuation<Void, Never>] = []
    private var entered = 0

    func pass() async {
        entered += 1
        await withCheckedContinuation { parked.append($0) }
    }

    func release() {
        let waiting = parked
        parked = []
        for continuation in waiting { continuation.resume() }
    }

    func waitUntilEntered(_ count: Int) async {
        while entered < count { await Task.yield() }
    }
}
