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
        // Deliverable because it is watched rather than registered: the rule it sidesteps
        // is about what RegisterEventHotKey will fire, and this never goes near it.
        #expect(HotkeyBinding.functionHold.isDeliverable)
    }

    /// The rule this suite used to assert was the opposite, and it is worth saying why it
    /// turned over rather than quietly rewriting the expectation.
    ///
    /// The old reasoning was that ⌘, ⌥, ⌃ and ⇧ are pressed dozens of times a minute in
    /// ordinary typing, so a dictation beginning on any of them would be unusable. That
    /// is true of a *single* modifier — and it was applied to every modifier-only
    /// binding, which swept up ⌃⌥ and ⌘⌥ and the rest. Those are combinations nobody
    /// presses by accident, that other dictation apps offer, and that people ask for.
    ///
    /// The question a binding type can answer is whether something can be *delivered*.
    /// Whether a particular choice is a good idea is the owner of the Mac's to make.
    @Test("any modifier combination can be held, including one on its own")
    func everyModifierCodeIsAHold() {
        // 54–63: ⌘ ⇧ ⌥ ⌃ left and right, Caps Lock, Fn.
        for keyCode: UInt16 in [54, 55, 56, 57, 58, 59, 60, 61, 62, 63] {
            let binding = HotkeyBinding(keyCode: keyCode, modifiers: [])
            #expect(binding.heldModifier != nil, "key \(keyCode) was not treated as a hold")
            #expect(binding.isDeliverable, "key \(keyCode) was refused")
        }
    }

    @Test("a modifier combination is a hold, and carries the modifiers it names")
    func combinationsAreHolds() {
        // What somebody pressing ⌃⌥ in the shortcut field actually produces: a modifier's
        // own key code, with the flags that were down alongside it.
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
        // The distinction matters to the monitor: `isFunctionHold` selects the `.function`
        // flag, and anything else selects the flags its modifiers name. Fn's key code
        // arriving with ⌘ down means ⌘ is what is being held.
        #expect(!binding.isFunctionHold)
    }

    @Test("a key that no keyboard can send is still refused")
    func syntheticKeyCodesAreRefused() {
        // The one thing left in `isDeliverable` that refuses anything. Not policy: there
        // is no such key to press.
        let binding = HotkeyBinding(keyCode: 0x80, modifiers: [.command])
        #expect(binding.heldModifier == nil)
        #expect(!binding.isDeliverable)
    }

    @Test("an ordinary key still needs a modifier")
    func bareKeysAreRefused() {
        // Unchanged, and for a reason that has nothing to do with taste: a registered
        // hot key with no modifier is accepted by the window server and then never fired.
        let binding = HotkeyBinding(keyCode: 9, modifiers: [])
        #expect(!binding.isUsable)
        #expect(!binding.isDeliverable)
    }
}
