import Foundation
import Synchronization
import Testing

@testable import UttrflowInput

/// A copied secret does not stay on the system clipboard for hours.
@Suite("Clearing a copied secret from the clipboard")
struct ConcealedClipboardClearTests {
    private static let secret = "sk-live-abcdef123456"

    /// A clock that never waits, and records each duration it is asked to wait.
    private final class Waits: Sendable {
        private let asked = Mutex<[Duration]>([])
        var durations: [Duration] { asked.withLock { $0 } }
        func record(_ duration: Duration) { asked.withLock { $0.append(duration) } }
    }

    @Test("an untouched clipboard is cleared after the delay")
    func clearsWhenUntouched() async {
        let pasteboard = FakePasteboard()
        let waits = Waits()
        let clear = ConcealedClipboardClear(sleep: { waits.record($0) })
        let written = pasteboard.setConcealedText(Self.secret)

        let task = clear.schedule(on: pasteboard, writtenAt: written.changeCount, afterSeconds: 60)

        #expect(await task?.value == true)
        #expect(pasteboard.text() == nil)
        #expect(waits.durations == [.seconds(60)])
    }

    @Test("a newer copy is never cleared")
    func keepsANewerCopy() async {
        let pasteboard = FakePasteboard()
        let clear = ConcealedClipboardClear(sleep: { _ in })
        let written = pasteboard.setConcealedText(Self.secret)
        _ = pasteboard.setText("something copied later")

        let task = clear.schedule(on: pasteboard, writtenAt: written.changeCount, afterSeconds: 60)

        #expect(await task?.value == false)
        #expect(pasteboard.text() == "something copied later")
    }

    @Test("a delay of zero schedules nothing")
    func offSchedulesNothing() {
        let pasteboard = FakePasteboard()
        let clear = ConcealedClipboardClear(sleep: { _ in })
        let written = pasteboard.setConcealedText(Self.secret)

        #expect(clear.schedule(on: pasteboard, writtenAt: written.changeCount, afterSeconds: 0) == nil)
        #expect(pasteboard.text() == Self.secret)
    }

    @Test("a write whose generation is unknown schedules nothing")
    func unknownGenerationSchedulesNothing() {
        let pasteboard = FakePasteboard()
        let clear = ConcealedClipboardClear(sleep: { _ in })
        _ = pasteboard.setConcealedText(Self.secret)

        #expect(clear.schedule(on: pasteboard, writtenAt: nil, afterSeconds: 60) == nil)
        #expect(pasteboard.text() == Self.secret)
    }

    @Test("a cancelled wait leaves the clipboard alone")
    func cancelledWaitKeeps() async {
        let pasteboard = FakePasteboard()
        let clear = ConcealedClipboardClear(sleep: { _ in throw CancellationError() })
        let written = pasteboard.setConcealedText(Self.secret)

        let task = clear.schedule(on: pasteboard, writtenAt: written.changeCount, afterSeconds: 60)

        #expect(await task?.value == false)
        #expect(pasteboard.text() == Self.secret)
    }
}
