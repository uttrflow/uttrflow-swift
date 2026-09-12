// Tests for HotkeyBinding's held-key rules.

import Testing

@testable import UttrflowCore

/// Holding keys rather than combining them, which is a different kind of trigger.
@Suite("Holding a key rather than combining one")
struct HotkeyHoldTests {
    @Test("Fn on its own is usable and deliverable")
    func functionHoldIsAllowed() {
        #expect(HotkeyBinding.functionHold.heldModifier != nil)
        #expect(HotkeyBinding.functionHold.isUsable)
        #expect(HotkeyBinding.functionHold.isFunctionHold)
        // Deliverable because it is watched rather than registered; RegisterEventHotKey never sees it.
        #expect(HotkeyBinding.functionHold.isDeliverable)
    }

    /// Whether a binding can be delivered is the type's question; whether it is wise is the Mac owner's.
    @Test("any modifier combination can be held, including one on its own")
    func everyModifierCodeIsAHold() {
        // 54–63 less Caps Lock: ⌘ ⇧ ⌥ ⌃ left and right, and Fn.
        for keyCode: UInt16 in [54, 55, 56, 58, 59, 60, 61, 62, 63] {
            let binding = HotkeyBinding(keyCode: keyCode, modifiers: [])
            #expect(binding.heldModifier != nil, "key \(keyCode) was not treated as a hold")
            #expect(binding.isDeliverable, "key \(keyCode) was refused")
        }
    }

    @Test("Caps Lock cannot be held, because nothing reports it")
    func capsLockIsRefused() {
        // It sets no modifier flag, so a watcher would read it as nothing held and fire constantly.
        #expect(!HotkeyBinding(keyCode: 57, modifiers: []).isDeliverable)
    }

    @Test("a modifier combination is a hold, and carries the modifiers it names")
    func combinationsAreHolds() {
        // What ⌃⌥ in the shortcut field produces: a modifier's own key code with the flags down alongside it.
        let controlOption = HotkeyBinding(keyCode: 58, modifiers: [.control, .option])
        #expect(controlOption.heldModifier != nil)
        #expect(controlOption.isDeliverable)
        #expect(!controlOption.isFunctionHold, "it is not Fn, so it is watched by its own flags")
        #expect(controlOption.modifiers == [.control, .option])
    }

    @Test("Fn's code with modifiers is a hold of those modifiers, not of Fn")
    func fnCodeWithModifiers() {
        let binding = HotkeyBinding(keyCode: HotkeyBinding.functionKeyCode, modifiers: [.command])
        #expect(binding.heldModifier != nil)
        // Fn's key code arriving with ⌘ down means ⌘ is what is held, so the monitor watches ⌘'s flag.
        #expect(!binding.isFunctionHold)
    }

    @Test("a key that no keyboard can send is still refused")
    func syntheticKeyCodesAreRefused() {
        // The one refusal left in `isDeliverable`, and not policy: there is no such key to press.
        let binding = HotkeyBinding(keyCode: 0x80, modifiers: [.command])
        #expect(binding.heldModifier == nil)
        #expect(!binding.isDeliverable)
    }

    @Test("an ordinary key still needs a modifier")
    func bareKeysAreRefused() {
        // A registered hot key with no modifier is accepted by the window server and then never fired.
        let binding = HotkeyBinding(keyCode: 9, modifiers: [])
        #expect(!binding.isUsable)
        #expect(!binding.isDeliverable)
    }

    @Test("a key code and modifiers that disagree are refused")
    func incoherentPairsAreRefused() {
        // The Option key paired with Command: what a recorder writes when it reads a key going up.
        let crossed = HotkeyBinding(keyCode: 58, modifiers: [.command])
        #expect(!crossed.isCoherent)
        #expect(!crossed.isDeliverable)
        // Fn is named by no modifier, so a combination may not claim it beside one.
        #expect(!HotkeyBinding(keyCode: 63, modifiers: [.option]).isCoherent)
        // Caps Lock names no modifier at all, so nothing can ever hold it down.
        #expect(!HotkeyBinding(keyCode: 57, modifiers: []).isCoherent)
    }

    @Test("a key code its own modifiers contain is kept")
    func coherentPairsAreKept() {
        #expect(HotkeyBinding.functionHold.isCoherent)
        #expect(HotkeyBinding(keyCode: 58, modifiers: [.option]).isCoherent)
        #expect(HotkeyBinding(keyCode: 58, modifiers: [.command, .option]).isCoherent)
        #expect(HotkeyBinding.optionSpace.isCoherent)
        #expect(HotkeyBinding.shiftCommandV.isCoherent)
    }
}
