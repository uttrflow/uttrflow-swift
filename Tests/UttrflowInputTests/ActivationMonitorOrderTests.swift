// Tests that a stop racing a keystroke still delivers the press before the release it owes.
import Dispatch
import Foundation
import Synchronization
import Testing

@testable import UttrflowCore
@testable import UttrflowInput

/// A keyboard that hands strokes to the monitor on whichever thread calls `send`.
private final class HandFedSource: KeyboardEventSource {
    private struct Sink: Sendable {
        let call: @Sendable (KeyEvent) -> Void
    }

    private struct State: Sendable {
        var sink: Sink?
        var consumesKeyDown = true
    }

    private let state = Mutex(State(sink: nil))

    func start(
        _ deliver: @escaping @Sendable (KeyEvent) -> Void,
        consumeKeyDown: Bool = false
    ) throws(KeyboardSourceError) {
        state.withLock {
            $0.sink = Sink(call: deliver)
            $0.consumesKeyDown = consumeKeyDown
        }
    }

    func stop() { state.withLock { $0.sink = nil } }

    func send(_ stroke: KeyEvent) { state.withLock { $0.sink }?.call(stroke) }

    var consumesKeyDown: Bool { state.withLock { $0.consumesKeyDown } }
}

/// Holds the source's thread once its stroke has left the lock, until the test lets it go.
private final class Turnstile: Sendable {
    let arrived = DispatchSemaphore(value: 0)
    let proceed = DispatchSemaphore(value: 0)

    func hold() {
        arrived.signal()
        proceed.wait()
    }
}

private let optionSpaceDown = KeyEvent(keyCode: 49, modifiers: [.option], phase: .down)

/// Sends ⌥Space down on a thread of its own and runs `interrupt` while that stroke is held past the lock.
@MainActor
private func raceAPress(interrupt: (ActivationMonitor) throws -> Void) throws -> ActivationMonitor {
    let source = HandFedSource()
    let turnstile = Turnstile()
    let monitor = ActivationMonitor(source: source, strokeLeftLock: { turnstile.hold() })
    try monitor.start(binding: .optionSpace)

    let typed = DispatchSemaphore(value: 0)
    Thread {
        source.send(optionSpaceDown)
        typed.signal()
    }.start()

    turnstile.arrived.wait()
    try interrupt(monitor)
    turnstile.proceed.signal()
    typed.wait()
    monitor.stop()
    return monitor
}

/// The first two events the monitor delivered, which are already buffered when this is called.
private func firstTwo(_ monitor: ActivationMonitor) async -> [HotkeyEvent] {
    var events = monitor.events.makeAsyncIterator()
    var seen: [HotkeyEvent] = []
    for _ in 0..<2 {
        if let event = await events.next() { seen.append(event) }
    }
    return seen
}

@Suite("Activation monitor: stopping while a keystroke is in flight")
struct ActivationMonitorOrderTests {
    @Test("reports bare Escape without consuming it")
    @MainActor
    func bareEscapeIsForwarded() async throws {
        let source = HandFedSource()
        let monitor = ActivationMonitor(source: source, strokeLeftLock: {})
        try monitor.start(binding: .optionSpace)

        source.send(KeyEvent(keyCode: 53, phase: .down))
        var events = monitor.events.makeAsyncIterator()

        #expect(await events.next() == .escapePressed)
        #expect(!source.consumesKeyDown)
        monitor.stop()
    }

    @Test("a stop during a press delivers the press before the release it owes")
    @MainActor
    func stopDuringPress() async throws {
        let events = await firstTwo(try raceAPress { $0.stop() })
        #expect(events == [.pressed, .released])
    }

    @Test("a rebind during a press delivers the press before the release it owes")
    @MainActor
    func rebindDuringPress() async throws {
        let events = await firstTwo(try raceAPress { try $0.start(binding: .optionSpace) })
        #expect(events == [.pressed, .released])
    }
}
