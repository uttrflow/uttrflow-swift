// Tests that the keyboard tap keeps its delivery alive until its own thread can no longer call back.
import CoreFoundation
import Foundation
import Synchronization
import Testing

@testable import UttrflowInput

@Suite("The keyboard tap's delivery lifetime", .timeLimit(.minutes(1)))
struct SystemKeyboardLifetimeTests {
    /// A plain Mach port, which stands in for an event tap without needing Accessibility.
    private static func makePort(_: UnsafeMutableRawPointer, _: Bool) -> CFMachPort? {
        CFMachPortCreate(nil, { _, _, _, _ in }, nil, nil)
    }

    /// A one-shot signal, buffered so it may fire before anyone waits.
    private struct Signal {
        let stream: AsyncStream<Void>
        let fire: @Sendable () -> Void

        init() {
            let (stream, continuation) = AsyncStream<Void>.makeStream()
            self.stream = stream
            fire = {
                continuation.yield()
                continuation.finish()
            }
        }

        func wait() async {
            for await _ in stream { return }
        }
    }

    @Test("stopping while the tap's thread is mid-flight keeps the delivery until that thread is done")
    func stopWaitsForTheTapThread() async throws {
        let released = Signal()
        let entered = Signal()
        let gate = DispatchSemaphore(value: 0)
        weak var weakDelivery: Delivery?
        var tap: RunningTap?
        do {
            let delivery = Delivery()
            weakDelivery = delivery
            tap = RunningTap.create(
                delivery: delivery, makePort: Self.makePort, released: released.fire,
                beforeLoop: {
                    entered.fire()
                    gate.wait()
                })
        }
        tap?.run()
        await entered.wait()
        tap?.stop()
        #expect(weakDelivery != nil, "the delivery was freed while the tap's thread could still read it")
        gate.signal()
        await released.wait()
        #expect(weakDelivery == nil, "the delivery outlived its stopped tap")
        withExtendedLifetime(tap) {}
    }

    @Test("a tap stopped before it runs releases its delivery at once")
    func stopBeforeRunReleases() throws {
        let fired = Atomic<Bool>(false)
        weak var weakDelivery: Delivery?
        var tap: RunningTap?
        do {
            let delivery = Delivery()
            weakDelivery = delivery
            tap = RunningTap.create(
                delivery: delivery, makePort: Self.makePort,
                released: { fired.store(true, ordering: .relaxed) })
        }
        tap?.stop()
        tap?.stop()
        tap?.run()
        let didFire = fired.load(ordering: .relaxed)
        #expect(didFire)
        #expect(weakDelivery == nil)
        withExtendedLifetime(tap) {}
    }
}
