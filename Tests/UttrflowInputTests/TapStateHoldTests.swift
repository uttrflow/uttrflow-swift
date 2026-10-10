// Tests that keys pressed after a taken keystroke stay held while the accept runs with nothing armed.
import CoreGraphics
import Dispatch
import Synchronization
import Testing
import UttrflowCore
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

    /// A key-up for a virtual key code with no modifiers.
    private static func keyUp(_ code: CGKeyCode, flags: CGEventFlags = []) throws -> CGEvent {
        let event = try #require(CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false))
        event.flags = flags
        return event
    }

    @Test("Core Graphics is asked to change listening state only when it changes")
    func tapEnableChangesOnlyOnTransitions() {
        let state = Self.makeState()

        #expect(state.needsListeningUpdate(false))
        #expect(!state.needsListeningUpdate(false))
        #expect(state.needsListeningUpdate(true))
        #expect(!state.needsListeningUpdate(true))
        #expect(state.needsListeningUpdate(false))
    }

    @Test("concurrent listening changes apply to Core Graphics in state order")
    func concurrentListeningChangesStayOrdered() {
        let state = Self.makeState()
        let firstUpdateEntered = DispatchSemaphore(value: 0)
        let releaseFirstUpdate = DispatchSemaphore(value: 0)
        let secondObservedControlLock = DispatchSemaphore(value: 0)
        let secondUpdateFinished = DispatchSemaphore(value: 0)
        let applied = Mutex<[Bool]>([])
        let secondFoundLockUnavailable = Mutex<Bool>(false)

        DispatchQueue.global().async {
            _ = state.arm(.tab) { listening in
                applied.withLock { $0.append(listening) }
                firstUpdateEntered.signal()
                releaseFirstUpdate.wait()
            }
        }
        #expect(firstUpdateEntered.wait(timeout: .now() + 5) == .success)

        DispatchQueue.global().async {
            secondFoundLockUnavailable.withLock { $0 = !state.listeningControlIsAvailableForTesting() }
            secondObservedControlLock.signal()
            _ = state.arm([]) { listening in
                applied.withLock { $0.append(listening) }
                secondUpdateFinished.signal()
            }
        }
        #expect(secondObservedControlLock.wait(timeout: .now() + 5) == .success)
        #expect(secondFoundLockUnavailable.withLock { $0 }, "the first update must own the control lock")
        #expect(
            secondUpdateFinished.wait(timeout: .now() + 0.1) == .timedOut,
            "the second transition must wait until the first Core Graphics update finishes")
        releaseFirstUpdate.signal()
        #expect(secondUpdateFinished.wait(timeout: .now() + 5) == .success)
        #expect(applied.withLock { $0 } == [true, false])
        #expect(!state.isListening)
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

    @Test("a changed modifier does not release an accept repeat, while a different key is replayed")
    func modifierChangeKeepsAcceptRepeatSwallowed() throws {
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
        #expect(posted.map(\.0) == [49])
        #expect(posted.map(\.1) == [CGEventFlags.maskAlternate.rawValue])
    }

    @Test("Option-Tab repeats remain swallowed after Option is released")
    func optionTabRepeatAfterOptionRelease() throws {
        let state = Self.makeState()
        #expect(state.arm(.optionTab))
        #expect(state.takes(try Self.key(48, flags: .maskAlternate)))
        #expect(state.arm([]))
        #expect(state.takes(try Self.repeatKey(48, flags: .maskAlternate)))
        #expect(state.takes(try Self.repeatKey(48)))

        var posted: [Int64] = []
        #expect(!state.releaseHeldKeys { posted.append($0.getIntegerValueField(.keyboardEventKeycode)) })
        #expect(posted.isEmpty)
    }

    @Test("hold expiry replays queued keys in order before a later key passes through")
    func expiryReplaysQueuedKeys() throws {
        let clock = ManualClock()
        let state = Self.makeState(clock: clock)
        #expect(state.arm(.tab))
        #expect(state.takes(try Self.key(48)))
        #expect(state.arm([]))
        #expect(state.takes(try Self.key(48)))
        #expect(state.takes(try Self.key(0)))
        #expect(state.takes(try Self.key(1)))

        clock.advance(by: .nanoseconds(Int64(KeyHold.limitNanoseconds)))

        var posted: [Int64] = []
        #expect(
            !state.takes(
                try Self.key(36),
                postExpired: {
                    posted.append($0.getIntegerValueField(.keyboardEventKeycode))
                }))
        #expect(posted == [0, 1])
        #expect(!state.isListening)

        var replayedAgain: [Int64] = []
        #expect(
            !state.releaseHeldKeys { replayedAgain.append($0.getIntegerValueField(.keyboardEventKeycode)) })
        #expect(replayedAgain.isEmpty)
    }

    @Test("stopping clears the repeat key so a later hold reaches the application")
    func stopClearsAcceptRepeat() throws {
        let state = Self.makeState()
        #expect(state.arm(.tab))
        #expect(state.takes(try Self.key(48)))

        state.stop()

        #expect(!state.takes(try Self.repeatKey(48)))
    }

    @Test("accept repeats stay swallowed after releaseHeldKeys until the accept key is released")
    func acceptRepeatsStaySwallowedAfterReleaseUntilKeyUp() throws {
        let state = Self.makeState()
        #expect(state.arm(.tab))
        #expect(state.takes(try Self.key(48)))
        #expect(state.arm([]))
        var posted: [Int64] = []
        #expect(!state.releaseHeldKeys { posted.append($0.getIntegerValueField(.keyboardEventKeycode)) })
        #expect(posted.isEmpty)
        #expect(state.takes(try Self.repeatKey(48)))
        #expect(posted.isEmpty)
        #expect(!state.takes(try Self.keyUp(48)))
        #expect(!state.takes(try Self.repeatKey(48)))
        #expect(posted.isEmpty)
    }

    @Test("an accept repeat does not chain-accept a new ghost while the accept key is still held")
    func acceptRepeatDoesNotChainAcceptNewGhost() throws {
        let state = Self.makeState()
        #expect(state.arm(.tab))
        #expect(state.takes(try Self.key(48)))
        #expect(state.take() == [.swallowed(KeyStroke(keyCode: 48, modifiers: []))])
        #expect(state.arm([]))
        #expect(!state.releaseHeldKeys())
        #expect(state.arm(.tab))
        #expect(state.takes(try Self.repeatKey(48)))
        #expect(state.take().isEmpty)
        #expect(state.armed.load(ordering: .acquiring) & ArmedKeys.tab.rawValue != 0)
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

    /// The suggestion commands other than bare Tab, each with the key that presses it.
    private static let heldCommands: [(code: CGKeyCode, flags: CGEventFlags, slot: ArmedKeys)] = [
        (53, [], .escape), (53, .maskAlternate, .optionEscape),
        (125, .maskAlternate, .optionDownArrow), (126, .maskAlternate, .optionUpArrow),
        (48, .maskAlternate, .optionTab), (36, [], .return), (124, [], .rightArrow),
    ]

    /// A state partway through a Tab accept, with typing, a command and more typing held in the disarmed gap.
    private static func stateHolding(_ code: CGKeyCode, flags: CGEventFlags) throws -> TapState {
        let state = Self.makeState()
        #expect(state.arm(.tab))
        #expect(state.takes(try Self.key(48)))
        #expect(state.take() == [.swallowed(KeyStroke(.tab))])
        #expect(state.arm([]))
        #expect(state.takes(try Self.key(0)))
        #expect(state.takes(try Self.key(code, flags: flags)))
        #expect(state.takes(try Self.key(11)))
        return state
    }

    @Test(
        "a command held in the disarmed gap waits for the next offer and is taken by it",
        arguments: Self.heldCommands)
    func heldCommandIsTakenByNextOffer(code: CGKeyCode, flags: CGEventFlags, slot: ArmedKeys) throws {
        let state = try Self.stateHolding(code, flags: flags)

        var posted: [CGEvent] = []
        #expect(state.releaseHeldKeys { posted.append($0) })
        #expect(posted.map { $0.getIntegerValueField(.keyboardEventKeycode) } == [0])

        #expect(state.arm(slot, postHeldKey: { posted.append($0) }))
        #expect(posted.map { $0.getIntegerValueField(.keyboardEventKeycode) } == [0, Int64(code), 11])
        #expect(state.takes(posted[1]))
        #expect(state.take() == [.swallowed(try #require(ArmedKeys.stroke(of: slot)))])
    }

    @Test(
        "a command held in the disarmed gap reaches the app when the next arming offers nothing",
        arguments: Self.heldCommands)
    func heldCommandPassesWhenNothingIsOffered(code: CGKeyCode, flags: CGEventFlags, slot: ArmedKeys) throws {
        let state = try Self.stateHolding(code, flags: flags)

        var posted: [CGEvent] = []
        #expect(state.releaseHeldKeys { posted.append($0) })
        #expect(!state.arm([], postHeldKey: { posted.append($0) }))
        #expect(posted.map { $0.getIntegerValueField(.keyboardEventKeycode) } == [0, Int64(code), 11])
        #expect(!state.takes(posted[1]))
        #expect(state.take().isEmpty)
    }

    @Test("a command held while the next offer is already armed is replayed for it at once")
    func heldCommandIsReplayedForAnArmedOffer() throws {
        let state = try Self.stateHolding(53, flags: [])
        #expect(state.arm(.escape))

        var posted: [CGEvent] = []
        #expect(state.releaseHeldKeys { posted.append($0) })
        #expect(posted.map { $0.getIntegerValueField(.keyboardEventKeycode) } == [0, 53, 11])
        #expect(!state.hold.isWaiting)
    }
}
