// Tests for the ring that carries taken keystrokes from the tap's thread to the drain.
import Dispatch
import Foundation
import Synchronization
import Testing
import UttrflowPredict

@testable import UttrflowInput

/// A flag one thread raises and another watches.
private final class Flag: Sendable {
    let value = Atomic(false)
}

@Suite("The key interceptor's ring", .timeLimit(.minutes(1)))
struct TapStateRingTests {
    /// A state with a resumed source of its own, since libdispatch traps on freeing a suspended one.
    private static func makeState() -> TapState {
        let source = DispatchSource.makeUserDataAddSource(queue: DispatchQueue(label: "test.tap-ring"))
        source.resume()
        return TapState(signal: source)
    }

    /// Distinct keys to fill the ring with, so the order they come out in can be read.
    private static let keys: [ArmedKeys] = [
        .tab, .optionTab, .rightArrow, .return, .escape, .downArrow, .upArrow,
    ]

    /// The event the drain reports for a key.
    private static func event(_ key: ArmedKeys) -> InterceptedEvent? {
        ArmedKeys.stroke(of: key).map { .swallowed($0) }
    }

    @Test("keystrokes come out in the order they went in")
    func keepsOrder() {
        let state = Self.makeState()
        for key in Self.keys { state.enqueue(key.rawValue) }
        #expect(state.take() == Self.keys.compactMap(Self.event))
        #expect(state.take().isEmpty)
    }

    @Test(
        "a drain a whole ring behind keeps the oldest keystrokes and drops the newer ones until it catches up"
    )
    func overflowDropsTheNewest() {
        let state = Self.makeState()
        let sent = (0..<(TapState.capacity + 10)).map { Self.keys[$0 % Self.keys.count] }
        for key in sent { state.enqueue(key.rawValue) }
        #expect(state.take() == sent.prefix(TapState.capacity).compactMap(Self.event))

        #expect(state.enqueue(ArmedKeys.escape.rawValue))
        #expect(state.take() == [Self.event(.escape)].compactMap { $0 })
    }

    @Test("a full ring refuses a keystroke rather than writing over one the drain has not read")
    func fullRingRefuses() {
        let state = Self.makeState()
        for _ in 0..<TapState.capacity { #expect(state.enqueue(ArmedKeys.tab.rawValue)) }
        #expect(!state.enqueue(ArmedKeys.escape.rawValue))
    }

    @Test("the tap giving up is reported after the keystrokes before it, even with the ring full")
    func givingUpSurvivesAFullRing() {
        let state = Self.makeState()
        for _ in 0..<TapState.capacity { state.enqueue(ArmedKeys.tab.rawValue) }
        // Two disables inside the window, which is what makes the tap give up.
        #expect(state.shouldReEnable())
        #expect(!state.shouldReEnable())
        let events = state.take()
        #expect(events.count == TapState.capacity + 1)
        #expect(events.last == .stopped(.disabledTwice))
        #expect(state.take().isEmpty)
    }

    @Test("one thread writing while another drains delivers every keystroke once, in order")
    func concurrentProducerAndConsumer() {
        let state = Self.makeState()
        let total = 20_000
        let finished = Flag()
        let producer = Thread {
            for index in 0..<total {
                let slot = Self.keys[index % Self.keys.count].rawValue
                // The drain is behind only as long as it is busy, so offering again always lands.
                while !state.enqueue(slot) {}
            }
            finished.value.store(true, ordering: .releasing)
        }
        producer.start()

        var received: [InterceptedEvent] = []
        while !finished.value.load(ordering: .acquiring) { received += state.take() }
        received += state.take()

        let expected = (0..<total).compactMap { Self.event(Self.keys[$0 % Self.keys.count]) }
        #expect(received.count == expected.count)
        #expect(received == expected)
    }
}
