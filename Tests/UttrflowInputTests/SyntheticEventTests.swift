import CoreGraphics
import Testing

@testable import UttrflowInput

@Suite("The feature ignores the keys it types itself")
struct SyntheticEventTests {
    /// One key-down event, or nothing when the window server will not make one in this environment.
    private func keyDown(_ code: CGKeyCode) -> CGEvent? {
        CGEvent(keyboardEventSource: CGEventSource(stateID: .hidSystemState), virtualKey: code, keyDown: true)
    }

    @Test("A tagged event is recognised as the app's own.")
    func taggedIsOurs() throws {
        let event = try #require(keyDown(48))
        SyntheticEvent.tag(event)
        #expect(SyntheticEvent.isOurs(event))
    }

    @Test("An untagged event is treated as the user's, so real typing still wakes a turn.")
    func untaggedIsNotOurs() throws {
        let event = try #require(keyDown(48))
        #expect(!SyntheticEvent.isOurs(event))
    }

    @Test("Even a synthetic Tab, an accept key, is dropped, so acceptance can never feed itself.")
    func syntheticAcceptKeyIsDropped() throws {
        // 48 is Tab, the default accept key; tagging it is what the tap and monitor both drop on.
        let tab = try #require(keyDown(48))
        SyntheticEvent.tag(tab)
        #expect(SyntheticEvent.isOurs(tab))
    }
}
