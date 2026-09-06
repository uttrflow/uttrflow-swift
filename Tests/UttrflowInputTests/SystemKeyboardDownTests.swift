// Tests for reading whether the key a flags change names went down or came up.

import Testing
import UttrflowCore

@testable import UttrflowInput

/// A flags change says what is held afterwards, so the key's own modifier says which way it moved.
@Suite("Reading a modifier's direction")
struct SystemKeyboardDownTests {
    @Test("a modifier still in the set went down")
    func pressIsDown() {
        #expect(
            SystemKeyboard.isDown(
                keyCode: 58, phase: .modifiersChanged, modifiers: [.command, .option],
                isFunctionDown: false))
    }

    @Test("a modifier missing from the set came up")
    func releaseIsUp() {
        // Option's code with only Command left: Option is what just left.
        #expect(
            !SystemKeyboard.isDown(
                keyCode: 58, phase: .modifiersChanged, modifiers: [.command],
                isFunctionDown: false))
    }

    @Test("Fn follows its own flag, which no modifier names")
    func functionFollowsItsFlag() {
        #expect(
            SystemKeyboard.isDown(
                keyCode: 63, phase: .modifiersChanged, modifiers: [], isFunctionDown: true))
        #expect(
            !SystemKeyboard.isDown(
                keyCode: 63, phase: .modifiersChanged, modifiers: [], isFunctionDown: false))
    }

    @Test("a key that types something says so by its phase")
    func typingKeysFollowPhase() {
        #expect(SystemKeyboard.isDown(keyCode: 49, phase: .down, modifiers: [], isFunctionDown: false))
        #expect(!SystemKeyboard.isDown(keyCode: 49, phase: .up, modifiers: [], isFunctionDown: false))
    }
}
