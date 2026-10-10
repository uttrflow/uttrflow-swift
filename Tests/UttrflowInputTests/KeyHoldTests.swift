// Tests for the hold that keeps keys back while a taken keystroke is carried out.
import CoreGraphics
import Dispatch
import Synchronization
import Testing
import UttrflowTestSupport

@testable import UttrflowInput

@Suite("The key hold")
struct KeyHoldTests {
    /// A key-down for a virtual key code.
    private static func key(_ code: CGKeyCode) -> CGEvent? {
        CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)
    }

    /// The key codes of events, in order.
    private static func codes(_ events: [CGEvent]) -> [Int64] {
        events.map { $0.getIntegerValueField(.keyboardEventKeycode) }
    }

    @Test("a concurrent release cannot remove the suppression from a new live hold")
    func suppressionSurvivesConcurrentRelease() {
        let clock = PausingClock(pauseOnRead: 3)
        let hold = KeyHold(clock: clock)
        hold.begin()
        let beginFinished = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            hold.begin(suppressingUnarmedTab: true)
            beginFinished.signal()
        }

        let reachedPause = clock.paused.wait(timeout: .now() + .seconds(2)) == .success
        #expect(reachedPause)
        hold.release()
        clock.resume.signal()
        #expect(beginFinished.wait(timeout: .now() + .seconds(2)) == .success)

        #expect(hold.isHolding)
        #expect(hold.isHoldingBareTabAccept)
        hold.release()
        #expect(!hold.isHolding)
        #expect(!hold.isHoldingBareTabAccept)
    }

    @Test("nothing is held back until a keystroke is taken")
    func passesWhenIdle() throws {
        let clock = ManualClock()
        let hold = KeyHold(clock: clock)
        #expect(!hold.keep(try #require(Self.key(36))))
    }

    @Test("a Return pressed during a slow accept reaches the application after the typed completion")
    func returnAfterCompletion() async throws {
        let clock = ManualClock()
        let hold = KeyHold(clock: clock)
        var delivered: [String] = []
        hold.begin()
        #expect(hold.keep(try #require(Self.key(36))))
        // The fake typist finishes its text before the held Return is released.
        delivered.append("u ubuntu")
        hold.release { delivered.append("key \($0.getIntegerValueField(.keyboardEventKeycode))") }
        #expect(delivered == ["u ubuntu", "key 36"])
    }

    @Test("held keys are replayed oldest first, and once")
    func replaysInOrder() throws {
        let clock = ManualClock()
        let hold = KeyHold(clock: clock)
        hold.begin()
        for code: CGKeyCode in [0, 1, 36] { #expect(hold.keep(try #require(Self.key(code)))) }
        var posted: [CGEvent] = []
        hold.release { posted.append($0) }
        #expect(Self.codes(posted) == [0, 1, 36])
        posted = []
        hold.release { posted.append($0) }
        #expect(posted.isEmpty)
        #expect(!hold.keep(try #require(Self.key(36))))
    }

    @Test("a key arriving after expiry replays earlier held keys before passing through")
    func expiryReplaysHeldKeys() throws {
        let clock = ManualClock()
        let hold = KeyHold(clock: clock)
        hold.begin()
        #expect(hold.keep(try #require(Self.key(0))))
        #expect(hold.keep(try #require(Self.key(1))))
        clock.advance(by: .nanoseconds(Int64(KeyHold.limitNanoseconds)))

        var posted: [Int64] = []
        #expect(
            !hold.keep(
                try #require(Self.key(36)),
                postExpired: {
                    posted.append($0.getIntegerValueField(.keyboardEventKeycode))
                }))
        #expect(posted == [0, 1])

        posted = []
        hold.release { posted.append($0.getIntegerValueField(.keyboardEventKeycode)) }
        #expect(posted.isEmpty)
        #expect(!hold.keep(try #require(Self.key(49))))
        #expect(!hold.isHoldingBareTabAccept)
    }

    @Test("a normal hold replays keys in arrival order")
    func normalHoldReplaysInOrder() throws {
        let clock = ManualClock()
        let hold = KeyHold(clock: clock)
        hold.begin()
        for code: CGKeyCode in [1, 0, 36] {
            #expect(hold.keep(try #require(Self.key(code))))
        }

        var posted: [CGEvent] = []
        hold.release { posted.append($0) }
        #expect(Self.codes(posted) == [1, 0, 36])
    }

    @Test("a hold that outlives its limit lets keys through again")
    func expires() throws {
        let clock = ManualClock()
        let hold = KeyHold(clock: clock)
        hold.begin()
        clock.advance(by: .nanoseconds(Int64(KeyHold.limitNanoseconds) - 1))
        #expect(hold.keep(try #require(Self.key(0))))
        clock.advance(by: .nanoseconds(1))
        #expect(!hold.keep(try #require(Self.key(36))))
        #expect(!hold.keep(try #require(Self.key(36))))
    }

    @Test("release drains a key whose eligibility check is in progress")
    func keepAndReleaseAreAtomic() throws {
        let clock = ManualClock()
        let hold = KeyHold(clock: clock)
        let enteredEligibilityCheck = DispatchSemaphore(value: 0)
        let finishKeep = DispatchSemaphore(value: 0)
        let releaseStarted = DispatchSemaphore(value: 0)
        let releaseFinished = DispatchSemaphore(value: 0)
        let keepResult = Mutex<Bool?>(nil)
        let posted = Mutex<[Int64]>([])
        hold.begin()

        DispatchQueue.global().async {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 36, keyDown: true) else {
                enteredEligibilityCheck.signal()
                keepResult.withLock { $0 = false }
                return
            }
            let kept = hold.keep(event) {
                enteredEligibilityCheck.signal()
                finishKeep.wait()
            }
            keepResult.withLock { $0 = kept }
        }
        enteredEligibilityCheck.wait()

        DispatchQueue.global().async {
            releaseStarted.signal()
            hold.release { event in
                posted.withLock { $0.append(event.getIntegerValueField(.keyboardEventKeycode)) }
            }
            releaseFinished.signal()
        }
        releaseStarted.wait()
        finishKeep.signal()
        releaseFinished.wait()

        #expect(keepResult.withLock { $0 } == true)
        #expect(posted.withLock { $0 } == [36])
        #expect(!hold.isHolding)
        #expect(!hold.keep(try #require(Self.key(49))))
        var replayedAgain: [Int64] = []
        hold.release { replayedAgain.append($0.getIntegerValueField(.keyboardEventKeycode)) }
        #expect(replayedAgain.isEmpty)
    }
}

/// Pauses the rearm's clock read so a concurrent release can finish before it publishes a new hold.
private final class PausingClock: Clock, Sendable {
    typealias Instant = ManualClock.Instant

    private let reads = Mutex(0)
    private let clock = ManualClock()
    private let pauseOnRead: Int
    let paused = DispatchSemaphore(value: 0)
    let resume = DispatchSemaphore(value: 0)

    init(pauseOnRead: Int) { self.pauseOnRead = pauseOnRead }

    var now: Instant {
        let read = reads.withLock { reads -> Int in
            reads += 1
            return reads
        }
        if read == pauseOnRead {
            paused.signal()
            resume.wait()
        }
        return clock.now
    }

    var minimumResolution: Duration { clock.minimumResolution }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        try await clock.sleep(until: deadline, tolerance: tolerance)
    }
}
