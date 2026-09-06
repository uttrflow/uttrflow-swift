import Testing

@testable import UttrflowCore

/// Recognising each shape of shortcut from keystrokes alone, which needs no window server.
@Suite("Recognising a shortcut")
struct HotkeyRecogniserTests {
    /// Modifiers changing, which is the only way a modifier reports itself.
    private func held(
        _ modifiers: Set<HotkeyModifier>, fn: Bool = false, keyCode: UInt16 = 0
    )
        -> KeyStroke
    {
        KeyStroke(
            keyCode: keyCode, modifiers: modifiers, isFunctionDown: fn, phase: .modifiersChanged)
    }

    private func down(_ keyCode: UInt16, _ modifiers: Set<HotkeyModifier>) -> KeyStroke {
        KeyStroke(keyCode: keyCode, modifiers: modifiers, phase: .down)
    }

    @Test("Fn held on its own, which no NSEvent monitor ever reported")
    func functionHold() {
        var r = HotkeyRecogniser(binding: .functionHold)
        #expect(r.receive(held([], fn: true)) == .pressed)
        #expect(r.receive(held([], fn: true)) == nil)
        #expect(r.receive(held([])) == .released)
    }

    @Test("one modifier held on its own")
    func singleModifierHold() {
        var r = HotkeyRecogniser(binding: HotkeyBinding(keyCode: 55, modifiers: []))
        #expect(r.receive(held([.command])) == .pressed)
        #expect(r.receive(held([])) == .released)
    }

    @Test("two modifiers held together, and neither one alone")
    func twoModifierHold() {
        var r = HotkeyRecogniser(
            binding: HotkeyBinding(keyCode: 58, modifiers: [.control, .option]))
        #expect(r.receive(held([.control])) == nil)
        #expect(r.receive(held([.control, .option])) == .pressed)
        #expect(r.receive(held([.control])) == .released)
    }

    @Test("three modifiers held together")
    func threeModifierHold() {
        var r = HotkeyRecogniser(
            binding: HotkeyBinding(keyCode: 56, modifiers: [.control, .option, .shift]))
        #expect(r.receive(held([.control, .option])) == nil)
        #expect(r.receive(held([.control, .option, .shift])) == .pressed)
        #expect(r.receive(held([])) == .released)
    }

    @Test("a modifier and a key, which used to need a different monitor entirely")
    func combination() {
        var r = HotkeyRecogniser(binding: .optionSpace)
        #expect(r.receive(held([.option])) == nil)
        #expect(r.receive(down(49, [.option])) == .pressed)
        #expect(r.receive(held([])) == .released)
    }

    @Test("a combination does not fire for the right key with the wrong modifiers")
    func combinationRefusesWrongModifiers() {
        var r = HotkeyRecogniser(binding: .optionSpace)
        #expect(r.receive(down(49, [.command])) == nil)
        #expect(r.receive(down(49, [])) == nil)
        #expect(!r.isDown)
    }

    @Test("Fn does not fire a modifier binding, and a modifier does not fire Fn")
    func shapesDoNotCrossFire() {
        var fn = HotkeyRecogniser(binding: .functionHold)
        #expect(fn.receive(held([.command])) == nil)
        var command = HotkeyRecogniser(binding: HotkeyBinding(keyCode: 55, modifiers: []))
        #expect(command.receive(held([], fn: true)) == nil)
    }

    @Test("a hold interrupted by stopping still owes its release, or the microphone stays open")
    func finishOwesARelease() {
        var r = HotkeyRecogniser(binding: .functionHold)
        #expect(r.receive(held([], fn: true)) == .pressed)
        #expect(r.finish() == .released)
        #expect(r.finish() == nil)
    }

    @Test("repeated readings of the same state report nothing, however many arrive")
    func repeatsAreQuiet() {
        var r = HotkeyRecogniser(binding: .optionSpace)
        _ = r.receive(down(49, [.option]))
        for _ in 0..<5 { #expect(r.receive(down(49, [.option])) == nil) }
        #expect(r.isDown)
    }
}
