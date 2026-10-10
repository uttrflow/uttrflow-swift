// Tests that the engine's input count rises once for each key or click between two readings, and never otherwise.

import Synchronization
import Testing
import UttrflowTestSupport

@testable import UttrflowContext

/// When the last key or click came, as time on the test's clock.
private final class LastInput: Sendable {
    private let at: Mutex<Duration>
    init(at: Duration) { self.at = Mutex(at) }
    var value: Duration {
        get { at.withLock { $0 } }
        set { at.withLock { $0 = newValue } }
    }
}

@Suite("The context engine's input count")
struct InputCountTests {
    /// A count over a clock the test moves, whose last key or click came at `lastInput` on that clock.
    private static func count(clock: ManualClock, lastInput: LastInput) -> InputCount {
        InputCount(clock: clock) {
            ManualClock.Instant(offset: .zero).duration(to: clock.now) - lastInput.value
        }
    }

    @Test("a key or click before the first reading does not raise the count")
    func inputBeforeTheFirstReadingIsNotCounted() {
        let clock = ManualClock()
        clock.advance(by: .seconds(5))
        let count = Self.count(clock: clock, lastInput: LastInput(at: .seconds(4)))

        #expect(count.value == 0)
        clock.advance(by: .seconds(1))
        #expect(count.value == 0, "no input came between the two readings")
    }

    @Test("a key or click after a reading raises the next one by one")
    func inputAfterAReadingIsCounted() {
        let clock = ManualClock()
        let lastInput = LastInput(at: .zero)
        let count = Self.count(clock: clock, lastInput: lastInput)
        clock.advance(by: .seconds(1))
        #expect(count.value == 0)

        clock.advance(by: .milliseconds(300))
        lastInput.value = .milliseconds(1_200)
        clock.advance(by: .milliseconds(300))

        #expect(count.value == 1)
        #expect(count.value == 1, "the same key is not counted twice")
    }

    @Test("an engine given no input count watches none")
    func anEngineWithoutACountWatchesNothing() async {
        let engine = MacContextEngine(
            readFrontmostApplication: { nil }, readFocusedWindow: { _, _ in },
            ownBundleIdentifier: nil, ownProcessIdentifier: 1)

        #expect(await engine.inputsSeen() == nil)
    }
}
