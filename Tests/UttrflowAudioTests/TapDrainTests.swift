// Tests the bounded key-up wait that recovers the block the hardware was still filling.
import Synchronization
import Testing

@testable import UttrflowAudio
@testable import UttrflowCore
import UttrflowTestSupport

@Suite("TapDrain")
struct TapDrainTests {
    /// A clock that jumps to each deadline and records every slice slept, so a test reads the schedule without spending it.
    private final class Pauses: Clock, Sendable {
        let slices = Mutex<[Duration]>([])
        private let manual = ManualClock(advancesWhenSlept: true)
        private let onSleep: @Sendable () -> Void

        init(onSleep: @escaping @Sendable () -> Void = {}) {
            self.onSleep = onSleep
        }

        var total: Duration { slices.withLock { $0.reduce(.zero, +) } }
        var now: ManualClock.Instant { manual.now }
        var minimumResolution: Duration { manual.minimumResolution }

        func sleep(until deadline: ManualClock.Instant, tolerance: Duration?) async throws {
            let slice = manual.now.duration(to: deadline)
            slices.withLock { $0.append(slice) }
            try await manual.sleep(until: deadline, tolerance: tolerance)
            onSleep()
        }
    }

    @Test("sizes the window from the tap buffer and the rate, not from a constant")
    func windowFollowsTheTap() {
        #expect(TapDrain.window(tapFrames: 4096, sampleRate: 48000) == .seconds(4096.0 / 48000.0))
        #expect(TapDrain.window(tapFrames: 2048, sampleRate: 48000) == .seconds(2048.0 / 48000.0))
        #expect(TapDrain.window(tapFrames: 4096, sampleRate: 44100) == .seconds(4096.0 / 44100.0))
    }

    /// A device that misreports its rate would otherwise hold key-up open for as long as it liked.
    @Test("caps the window so a wedged device cannot hold key-up open")
    func windowIsCapped() {
        #expect(TapDrain.window(tapFrames: 4096, sampleRate: 1) == TapDrain.cap)
        #expect(TapDrain.window(tapFrames: 4096, sampleRate: 0) == .zero)
        #expect(TapDrain.window(tapFrames: 0, sampleRate: 48000) == .zero)
    }

    @Test("waits out the whole window when no block ever arrives")
    func waitsTheFullWindowWhenNothingArrives() async {
        let pauses = Pauses()
        let drain = TapDrain(step: .milliseconds(5), clock: pauses)

        await drain.wait(.milliseconds(85))

        #expect(pauses.total == .milliseconds(85))
    }

    @Test("returns as soon as the tap hands over a block")
    func returnsOnTheNextBlock() async {
        let held = Mutex<TapDrain?>(nil)
        let pauses = Pauses { held.withLock { $0 }?.blockDelivered() }
        let drain = TapDrain(step: .milliseconds(5), clock: pauses)
        held.withLock { $0 = drain }

        await drain.wait(.milliseconds(250))

        #expect(drain.deliveredCount == 1)
        #expect(pauses.total == .milliseconds(5), "the wait ended on the block, not on the window")
    }

    @Test("waits for nothing when the window is empty")
    func emptyWindowDoesNotWait() async {
        let pauses = Pauses()
        let drain = TapDrain(step: .milliseconds(5), clock: pauses)

        await drain.wait(.zero)

        #expect(pauses.slices.withLock { $0.isEmpty })
    }

    /// The last slice is trimmed rather than overshooting, which is what makes the cap a cap.
    @Test("never waits longer than the window it was given")
    func neverOvershootsTheWindow() async {
        let pauses = Pauses()
        let drain = TapDrain(step: .milliseconds(20), clock: pauses)

        await drain.wait(.milliseconds(50))

        #expect(pauses.total == .milliseconds(50))
        #expect(pauses.slices.withLock { $0 } == [.milliseconds(20), .milliseconds(20), .milliseconds(10)])
    }
}
