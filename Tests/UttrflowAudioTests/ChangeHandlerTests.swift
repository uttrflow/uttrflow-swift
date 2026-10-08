// Tests that the microphone's hardware-change handler costs a flat stack and reaches only the live engine.
import Testing

@testable import UttrflowAudio

@Suite("The microphone's hardware-change handler")
struct ChangeHandlerTests {
    /// The address of a local in a frame of its own, which is how deep the stack is where it is called.
    @inline(never)
    private static func stackAddress() -> Int {
        var marker: UInt8 = 0
        return withUnsafeMutablePointer(to: &marker) { Int(bitPattern: $0) }
    }

    /// Where the handler found the stack, written and read on the test's own thread.
    private final class Depth: @unchecked Sendable {
        var address = 0
    }

    @Test("the handler read at the 500th open runs no deeper in the stack than the one read at the first")
    func readingDoesNotDeepenTheStack() {
        let handler = ChangeHandler()
        let depth = Depth()
        handler.set { depth.address = ChangeHandlerTests.stackAddress() }

        var first = 0
        for count in 1...500 {
            handler.current()?()
            if count == 1 { first = depth.address }
        }

        #expect(first != 0, "the handler was never called")
        let growth = first - depth.address
        #expect(growth < 4096, "stack growth, read 1 -> read 500: \(growth) bytes")
    }

    @Test("nothing is handed back before a handler is set")
    func emptyUntilSet() {
        #expect(ChangeHandler().current() == nil)
    }

    /// Which engine is live and how many notices got through, shared with the handler.
    private final class Engines: @unchecked Sendable {
        var live = 1
        var calls = 0
    }

    @Test("a notice queued for a closed engine does not reach the engine opened after it")
    func staleNoticeIsDropped() {
        let handler = ChangeHandler()
        let engines = Engines()
        handler.set { engines.calls += 1 }
        let first = handler.current { engines.live == 1 }
        engines.live = 2
        let second = handler.current { engines.live == 2 }

        first()
        #expect(engines.calls == 0)
        second()
        #expect(engines.calls == 1)
    }
}
