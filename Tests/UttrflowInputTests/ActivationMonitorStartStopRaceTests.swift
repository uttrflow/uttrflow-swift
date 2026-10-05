// Tests that a stop overlapping a start leaves the new shortcut recognising presses.
import Dispatch
import Foundation
import Synchronization
import Testing

@testable import UttrflowCore
@testable import UttrflowInput

/// A keyboard whose next stop can be held open until the test lets it finish.
private final class PausableSource: KeyboardEventSource {
    private struct Sink: Sendable {
        let call: @Sendable (KeyEvent) -> Void
    }

    private let sink = Mutex<Sink?>(nil)
    private let pauseNextStop = Mutex(false)
    let stopped = DispatchSemaphore(value: 0)
    let resume = DispatchSemaphore(value: 0)

    func start(
        _ deliver: @escaping @Sendable (KeyEvent) -> Void,
        consumeKeyDown: Bool = false
    ) throws(KeyboardSourceError) {
        sink.withLock { $0 = Sink(call: deliver) }
    }

    func stop() {
        sink.withLock { $0 = nil }
        let pause = pauseNextStop.withLock { flag in
            defer { flag = false }
            return flag
        }
        if pause {
            stopped.signal()
            resume.wait()
        }
    }

    func holdNextStop() { pauseNextStop.withLock { $0 = true } }

    func send(_ stroke: KeyEvent) { sink.withLock { $0 }?.call(stroke) }
}

private let optionSpaceDown = KeyEvent(keyCode: 49, modifiers: [.option], phase: .down)

/// Pauses a stop on another thread just past the source, runs a start to completion, then lets the stop finish.
@MainActor
private func stopOverlappingAStart(
    _ monitor: ActivationMonitor, on source: PausableSource
) throws {
    source.holdNextStop()
    let finished = DispatchSemaphore(value: 0)
    Thread { [weak monitor] in
        monitor?.stop()
        finished.signal()
    }.start()
    source.stopped.wait()
    try monitor.start(binding: .optionSpace)
    source.resume.signal()
    finished.wait()
}

@Suite("Activation monitor: a stop overlapping a start")
struct ActivationMonitorStartStopRaceTests {
    @Test("a stop paused past the source while a start completes leaves the shortcut live")
    @MainActor
    func stalledStopDoesNotSilenceTheNewStart() async throws {
        let source = PausableSource()
        var monitor: ActivationMonitor? = ActivationMonitor(source: source)
        var events = try #require(monitor).events.makeAsyncIterator()
        try monitor?.start(binding: .optionSpace)
        try stopOverlappingAStart(try #require(monitor), on: source)

        source.send(optionSpaceDown)
        monitor = nil
        #expect(await events.next() == .pressed)
    }
}
