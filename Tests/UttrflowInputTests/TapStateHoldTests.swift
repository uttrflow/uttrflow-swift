// Tests that keys pressed after a taken keystroke stay held while the accept runs with nothing armed.
import CoreGraphics
import Dispatch
import Testing
import UttrflowTestSupport
import UttrflowPredict

@testable import UttrflowInput

@Suite("The tap while a taken keystroke is carried out")
struct TapStateHoldTests {
    /// A state with a resumed source of its own, since libdispatch traps on freeing a suspended one.
    private static func makeState(clock: ManualClock? = nil) -> TapState {
        let source = DispatchSource.makeUserDataAddSource(queue: DispatchQueue(label: "test.tap-hold"))
        source.resume()
        if let clock { return TapState(signal: source, clock: clock) }
        return TapState(signal: source)
    }

    /// A key-down for a virtual key code with no modifiers.
    private static func key(_ code: CGKeyCode, flags: CGEventFlags = []) throws -> CGEvent {
        let event = try #require(CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true))
        event.flags = flags
        return event
    }

    private static func repeatKey(_ code: CGKeyCode, flags: CGEventFlags = []) throws -> CGEvent {
        let event = try Self.key(code, flags: flags)
        event.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
        return event
    }

    @Test("a key pressed after Tab is held even once the accept disarms every slot, and replayed on release")
    func heldThroughDisarm() throws {
        let state = Self.makeState()
        #expect(state.arm(.tab))
        #expect(state.takes(try Self.key(48)))
        // The accept path disarms before it inserts; the tap must keep listening so the hold still works.
        #expect(state.arm([]))
        #expect(state.takes(try Self.key(49)))
        #expect(state.takes(try Self.key(45)))
        var posted: [Int64] = []
        let listening = state.releaseHeldKeys {
            posted.append($0.getIntegerValueField(.keyboardEventKeycode))
        }
        #expect(posted == [49, 45])
        #expect(!listening)
        #expect(!state.takes(try Self.key(49)))
    }

    @Test("a held Tab is discarded during the disarmed accept gap, while ordinary typing is replayed")
    func tabDoesNotLeakDuringDisarmedGap() throws {
        let state = Self.makeState()
        #expect(state.arm(.tab))
        #expect(state.takes(try Self.key(48)))
        #expect(state.arm([]))
        #expect(state.takes(try Self.key(48)))
        #expect(state.takes(try Self.key(0)))

        var posted: [Int64] = []
        #expect(
            !state.releaseHeldKeys {
                posted.append($0.getIntegerValueField(.keyboardEventKeycode))
            })
        #expect(posted == [0])
    }

    @Test("a held Tab is re-evaluated when the next offer is armed before release")
    func tabIsReevaluatedAgainstRearmedOffer() throws {
        let state = Self.makeState()
        #expect(state.arm(.tab))
        #expect(state.takes(try Self.key(48)))
        // The interceptor drains each taken key on its signal, so the first Tab is delivered before the accept runs.
        #expect(state.take() == [.swallowed(KeyStroke(keyCode: 48, modifiers: []))])
        #expect(state.arm([]))
        #expect(state.takes(try Self.key(48)))
        #expect(state.arm(.tab))
        #expect(state.armed.load(ordering: .acquiring) & ArmedKeys.tab.rawValue != 0)

        var replayedAndTaken = false
        #expect(
            state.releaseHeldKeys { event in
                replayedAndTaken = state.takes(event)
            })
        #expect(replayedAndTaken)
        #expect(state.take() == [.swallowed(KeyStroke(keyCode: 48, modifiers: []))])
    }

    @Test("a bare Tab remains an application key when the accepted key was not Tab")
    func tabAfterDifferentAcceptIsPreserved() throws {
        let state = Self.makeState()
        #expect(state.arm(.rightArrow))
        #expect(state.takes(try Self.key(124)))
        #expect(state.arm([]))
        #expect(state.takes(try Self.key(48)))

        var posted: [Int64] = []
        #expect(!state.releaseHeldKeys { posted.append($0.getIntegerValueField(.keyboardEventKeycode)) })
        #expect(posted == [48])
    }

    @Test("with nothing armed and nothing held, the tap is off and every key passes")
    func idleTapIsOff() throws {
        let state = Self.makeState()
        #expect(!state.arm([]))
        #expect(!state.takes(try Self.key(48)))
    }

    @Test("accept-key repeats stay swallowed before and after release")
    func acceptRepeatsStaySwallowed() throws {
        let state = Self.makeState()
        #expect(state.arm(.tab))
        #expect(state.takes(try Self.key(48)))
        #expect(state.takes(try Self.repeatKey(48)))
        #expect(state.arm([]))
        #expect(state.takes(try Self.repeatKey(48)))
        var posted: [Int64] = []
        #expect(!state.releaseHeldKeys { posted.append($0.getIntegerValueField(.keyboardEventKeycode)) })
        #expect(posted.isEmpty)
    }

    @Test("a different key or modifier set is held and replayed instead of swallowed as an accept repeat")
    func differentStrokeIsNotSwallowedAsARepeat() throws {
        let state = Self.makeState()
        #expect(state.arm(.tab))
        #expect(state.takes(try Self.key(48)))
        #expect(state.arm([]))
        #expect(state.takes(try Self.repeatKey(48, flags: .maskAlternate)))
        #expect(state.takes(try Self.repeatKey(49, flags: .maskAlternate)))

        var posted: [(Int64, UInt64)] = []
        #expect(
            !state.releaseHeldKeys {
                posted.append(($0.getIntegerValueField(.keyboardEventKeycode), $0.flags.rawValue))
            })
        #expect(posted.map(\.0) == [48, 49])
        #expect(
            posted.map(\.1) == [
                CGEventFlags.maskAlternate.rawValue,
                CGEventFlags.maskAlternate.rawValue,
            ])
    }

    @Test("stopping clears the repeat key so a later hold reaches the application")
    func stopClearsAcceptRepeat() throws {
        let state = Self.makeState()
        #expect(state.arm(.tab))
        #expect(state.takes(try Self.key(48)))

        state.stop()

        #expect(!state.takes(try Self.repeatKey(48)))
    }

    @Test("accept repeats pass through once the hold expires")
    func expiredHoldClearsAcceptRepeat() throws {
        let clock = ManualClock()
        let state = Self.makeState(clock: clock)
        #expect(state.arm(.tab))
        #expect(state.takes(try Self.key(48)))
        #expect(state.arm([]))

        clock.advance(by: .nanoseconds(Int64(KeyHold.limitNanoseconds)))

        #expect(!state.takes(try Self.repeatKey(48)))
        #expect(!state.isListening)
    }

    @Test("an open native menu receives a key that the suggestion has armed")
    func nativeMenuReceivesArmedKey() throws {
        let state = Self.makeState()
        #expect(state.arm(.tab))
        state.setNativeMenuIsOpen(true)
        #expect(!state.takes(try Self.key(48)))
        #expect(state.armed.load(ordering: .acquiring) & ArmedKeys.tab.rawValue != 0)
    }
}
