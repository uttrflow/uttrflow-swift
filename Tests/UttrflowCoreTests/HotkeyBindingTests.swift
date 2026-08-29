import Testing

@testable import UttrflowCore

/// Holding Fn, which is a different kind of trigger from a combination.
@Suite("Holding a key rather than combining one")
struct HotkeyHoldTests {
    @Test("Fn on its own is usable and deliverable, unlike every other lone modifier")
    func functionHoldIsAllowed() {
        #expect(HotkeyBinding.functionHold.heldModifier != nil)
        #expect(HotkeyBinding.functionHold.isUsable)
        // Deliverable because it is watched rather than registered: the rule it sidesteps
        // is about what RegisterEventHotKey will fire, and this never goes near it.
        #expect(HotkeyBinding.functionHold.isDeliverable)
    }

    @Test("the other modifiers are still not holdable on their own")
    func otherModifiersAreNotHolds() {
        // Command, shift, option, control — left and right. Each is pressed dozens of
        // times a minute while typing, so a dictation that began on any of them would be
        // unusable in a way no setting could rescue.
        for keyCode: UInt16 in [54, 55, 56, 57, 58, 59, 60, 61, 62] {
            let binding = HotkeyBinding(keyCode: keyCode, modifiers: [])
            #expect(binding.heldModifier == nil, "key \(keyCode) was treated as a hold")
            #expect(!binding.isDeliverable, "key \(keyCode) was accepted")
        }
    }

    @Test("a combination that happens to use Fn's code with modifiers is not a hold")
    func fnWithModifiersIsNotAHold() {
        let binding = HotkeyBinding(keyCode: HotkeyBinding.functionKeyCode, modifiers: [.command])
        #expect(binding.heldModifier == nil)
        #expect(!binding.isDeliverable, "the window server would never fire it")
    }
}
