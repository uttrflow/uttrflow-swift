// Tests for the one translation of window-server flags into modifiers.

import CoreGraphics
import Testing
import UttrflowCore
import UttrflowPredict

@testable import UttrflowInput

/// Pins each modifier to its flag so both key-reading paths share one mapping.
@Suite("Decoding event flags into modifiers")
struct EventFlagModifiersTests {
    @Test("each modifier reads its own flag")
    func eachFlag() {
        #expect(HotkeyModifier.held(in: .maskCommand) == [.command])
        #expect(HotkeyModifier.held(in: .maskAlternate) == [.option])
        #expect(HotkeyModifier.held(in: .maskControl) == [.control])
        #expect(HotkeyModifier.held(in: .maskShift) == [.shift])
    }

    @Test("unrelated flags are ignored and all four read together")
    func combined() {
        #expect(HotkeyModifier.held(in: [.maskSecondaryFn, .maskAlphaShift]).isEmpty)
        let all: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
        #expect(HotkeyModifier.held(in: all) == [.command, .option, .control, .shift])
    }

    @Test("the system keyboard's stroke uses the shared decoding")
    func strokeAgrees() {
        let flags: CGEventFlags = [.maskCommand, .maskShift, .maskSecondaryFn]
        let stroke = SystemKeyboard.stroke(keyCode: 0, flags: flags, phase: .down)
        #expect(stroke.modifiers == Set(HotkeyModifier.held(in: flags)))
        #expect(stroke.isFunctionDown)
    }
}

/// The interceptor's option set reads the same four flags as the hotkey path.
@Suite("Decoding event flags into key modifiers")
struct KeyModifiersFlagTests {
    @Test("every combination agrees with the shared decoding")
    func agrees() {
        let flags: [CGEventFlags] = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
        for mask in 0..<16 {
            var combined: CGEventFlags = [.maskSecondaryFn]
            for (bit, flag) in flags.enumerated() where mask & (1 << bit) != 0 { combined.insert(flag) }
            var expected = KeyModifiers()
            let held = HotkeyModifier.held(in: combined)
            if held.contains(.command) { expected.insert(.command) }
            if held.contains(.option) { expected.insert(.option) }
            if held.contains(.control) { expected.insert(.control) }
            if held.contains(.shift) { expected.insert(.shift) }
            #expect(KeyModifiers(combined) == expected)
            #expect(held.count == mask.nonzeroBitCount)
        }
    }
}
