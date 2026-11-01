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
        let pause = ClipboardPause(until: start.addingTimeInterval(5), now: { self.start }, sleep: { _ in })
        let expired = expectation(description: "expired")
        pause.startTimerIfNeeded { expired.fulfill() }
        await fulfillment(of: [expired], timeout: 2)
        XCTAssertNil(pause.until)
    }

    func testCancelledTimerNeverFires() async {
        let pause = ClipboardPause(
            until: start.addingTimeInterval(5), now: { self.start },
            sleep: { _ in try await Task.sleep(for: .seconds(30)) })
        let expired = expectation(description: "expired")
        expired.isInverted = true
        pause.startTimerIfNeeded { expired.fulfill() }
        pause.set(false)
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
