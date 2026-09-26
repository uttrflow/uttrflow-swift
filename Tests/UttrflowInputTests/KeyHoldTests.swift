// Tests for the hold that keeps keys back while a taken keystroke is carried out.
import CoreGraphics
import Testing

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

    @Test("nothing is held back until a keystroke is taken")
    func passesWhenIdle() throws {
        let hold = KeyHold()
        #expect(!hold.keep(try #require(Self.key(36)), now: 10))
    }

    @Test("a Return pressed during a slow accept reaches the application after the typed completion")
    func returnAfterCompletion() async throws {
        let hold = KeyHold()
        var delivered: [String] = []
        hold.begin(now: 100)
        #expect(hold.keep(try #require(Self.key(36)), now: 200))
        // The fake typist finishes only after the Return was pressed.
        try await Task.sleep(for: .milliseconds(20))
        delivered.append("u ubuntu")
        hold.release { delivered.append("key \($0.getIntegerValueField(.keyboardEventKeycode))") }
        #expect(delivered == ["u ubuntu", "key 36"])
    }

    @Test("held keys are replayed oldest first, and once")
    func replaysInOrder() throws {
        let hold = KeyHold()
        hold.begin(now: 1)
        for code: CGKeyCode in [0, 1, 36] { #expect(hold.keep(try #require(Self.key(code)), now: 2)) }
        var posted: [CGEvent] = []
        hold.release { posted.append($0) }
        #expect(Self.codes(posted) == [0, 1, 36])
        posted = []
        hold.release { posted.append($0) }
        #expect(posted.isEmpty)
        #expect(!hold.keep(try #require(Self.key(36)), now: 3))
    }

    @Test("a hold that outlives its limit lets keys through again")
    func expires() throws {
        let hold = KeyHold()
        hold.begin(now: 5)
        #expect(!hold.keep(try #require(Self.key(36)), now: 5 + KeyHold.limitNanoseconds))
        #expect(!hold.keep(try #require(Self.key(36)), now: 6 + KeyHold.limitNanoseconds))
    }
}
