// Tests for drawing a shortcut on keycaps and for recording a new one.
import UttrflowCore
import Testing

@testable import UttrflowUX

@Suite("Drawing a shortcut on keycaps")
struct SettingsShortcutDrawingTests {
    @Test("draws modifiers in the platform's order, whatever order they were given in")
    func modifiersAreOrdered() {
        let binding = HotkeyBinding(
            keyCode: 49, modifiers: [.command, .control, .shift, .option])
        #expect(SettingsShortcut.keycaps(for: binding) == ["⌃", "⌥", "⇧", "⌘", "Space"])
        #expect(SettingsShortcut.compact(binding) == "⌃⌥⇧⌘Space")
    }

    @Test("draws the shipping shortcut the way the floating button already does")
    func drawsTheDefault() {
        #expect(SettingsShortcut.compact(.optionSpace) == "⌥Space")
    }

    @Test("names the keys a shortcut is likely to use")
    func namesCommonKeys() {
        #expect(SettingsShortcut.name(of: 40) == "K")
        #expect(SettingsShortcut.name(of: 36) == "Return")
        #expect(SettingsShortcut.name(of: 122) == "F1")
        #expect(SettingsShortcut.name(of: 126) == "↑")
    }

    /// A binding stored as its own modifier drew that modifier twice, once as a cap and once as the key.
    @Test("draws a held modifier as one key, whatever modifiers came stored beside it")
    func drawsAHeldModifierOnce() {
        #expect(SettingsShortcut.keycaps(for: HotkeyBinding(keyCode: 58, modifiers: [])) == ["⌥"])
        #expect(
            SettingsShortcut.keycaps(for: HotkeyBinding(keyCode: 58, modifiers: [.option])) == ["⌥"])
        #expect(SettingsShortcut.keycaps(for: .functionHold) == ["fn"])
        // A real combination still draws every cap it is made of.
        #expect(SettingsShortcut.keycaps(for: .optionSpace) == ["⌥", "Space"])
    }

    @Test("shows a key it has no name for as its code rather than as nothing")
    func namesTheUnnameable() {
        #expect(SettingsShortcut.name(of: 200) == "Key 200")
    }

    /// A held binding may be any modifier, so every one of those codes has to draw as a key.
    @Test(
        "names every modifier a held shortcut can be, rather than showing its code",
        arguments: [
            (UInt16(54), "⌘"), (55, "⌘"), (56, "⇧"), (57, "Caps Lock"), (58, "⌥"),
            (59, "⌃"), (60, "⇧"), (61, "⌥"), (62, "⌃"), (63, "fn"),
        ]
    )
    func namesEveryHeldModifier(keyCode: UInt16, drawn: String) {
        #expect(SettingsShortcut.name(of: keyCode) == drawn)
        #expect(!SettingsShortcut.name(of: keyCode).hasPrefix("Key "))
    }
}

@Suite("Recording a new shortcut")
struct SettingsShortcutRecorderTests {
    @Test("shows the shortcut in force until recording begins")
    func promptsWithTheCurrentShortcut() {
        var recorder = SettingsShortcutRecorder(binding: .optionSpace)
        #expect(recorder.prompt == "⌥Space")
        #expect(!recorder.isRecording)

        recorder.beginRecording()
        #expect(recorder.isRecording)
        #expect(recorder.prompt == "Press the new shortcut")
    }

    @Test("takes a deliverable combination and hands back the change to save")
    func recordsADeliverableShortcut() {
        var recorder = SettingsShortcutRecorder(binding: .optionSpace)
        recorder.beginRecording()
        let outcome = recorder.record(keyCode: 40, modifiers: [.command, .shift])

        let expected = HotkeyBinding(keyCode: 40, modifiers: [.command, .shift])
        #expect(outcome == .recorded(.shortcut(expected)))
        #expect(recorder.binding == expected)
        #expect(!recorder.isRecording)
        #expect(recorder.rejection == nil)
    }

    @Test("refuses an undeliverable combination and keeps the previous shortcut")
    func refusalLeavesTheOldShortcutInForce() {
        var recorder = SettingsShortcutRecorder(binding: .optionSpace)
        recorder.beginRecording()
        let outcome = recorder.record(keyCode: 40, modifiers: [])

        guard case .refused(let rejection) = outcome else {
            Issue.record("a shortcut with no modifier was accepted")
            return
        }
        #expect(recorder.binding == .optionSpace)
        #expect(recorder.rejection == rejection.reason)
        // Still listening: the user is one keystroke from a shortcut that works.
        #expect(recorder.isRecording)
    }

    /// A modifier held on its own is deliverable and accepted; Fn alone is the natural dictation trigger.
    @Test("takes Fn held on its own, which is a shortcut rather than a modifier")
    func functionHoldIsAccepted() {
        var recorder = SettingsShortcutRecorder(binding: .optionSpace)
        recorder.beginRecording()
        let outcome = recorder.record(keyCode: HotkeyBinding.functionKeyCode, modifiers: [])

        guard case .recorded(let change) = outcome else {
            Issue.record("holding Fn was refused: \(outcome)")
            return
        }
        #expect(change == .shortcut(.functionHold))
        #expect(recorder.binding == .functionHold)
        #expect(!recorder.isRecording, "a recorded shortcut ends the recording")
        #expect(SettingsShortcut.compact(.functionHold) == "fn")
    }

    /// Whether ⌘ alone is wise is the owner's choice; whether it can be delivered is this code's, and it can.
    @Test("accepts a modifier pressed on its own, and any combination of them")
    func heldModifiersAreAccepted() {
        for (keyCode, modifiers) in [
            (UInt16(55), Set<HotkeyModifier>([.command])),
            (UInt16(58), Set([.option])),
            (UInt16(59), Set([.control])),
            (UInt16(56), Set([.shift])),
            // The combination this was all about.
            (UInt16(58), Set([.control, .option])),
            (UInt16(55), Set([.command, .option])),
            (UInt16(59), Set([.control, .option, .command])),
        ] {
            var recorder = SettingsShortcutRecorder(binding: .optionSpace)
            recorder.beginRecording()
            let outcome = recorder.record(keyCode: keyCode, modifiers: modifiers)

            guard case .refused(let rejection) = outcome else {
                #expect(recorder.binding == HotkeyBinding(keyCode: keyCode, modifiers: modifiers))
                continue
            }
            Issue.record("\(modifiers) was refused: \(rejection.reason)")
        }
    }

    @Test("a refusal followed by a good combination ends with the good one")
    func recoversFromARefusal() {
        var recorder = SettingsShortcutRecorder(binding: .optionSpace)
        recorder.beginRecording()
        // 0x80 is past the virtual key range: the one thing still refused outright.
        _ = recorder.record(keyCode: 0x80, modifiers: [.option])
        #expect(recorder.rejection != nil)

        _ = recorder.record(keyCode: 8, modifiers: [.control, .option])
        #expect(recorder.binding == HotkeyBinding(keyCode: 8, modifiers: [.control, .option]))
        #expect(recorder.rejection == nil)
    }

    @Test("Escape on its own leaves the shortcut alone")
    func escapeCancels() {
        var recorder = SettingsShortcutRecorder(binding: .optionSpace)
        recorder.beginRecording()
        #expect(recorder.record(keyCode: 53, modifiers: []) == .cancelled)
        #expect(recorder.binding == .optionSpace)
        #expect(!recorder.isRecording)
    }

    @Test("Escape with a modifier is a shortcut like any other")
    func modifiedEscapeIsBindable() {
        var recorder = SettingsShortcutRecorder(binding: .optionSpace)
        recorder.beginRecording()
        _ = recorder.record(keyCode: 53, modifiers: [.command])
        #expect(recorder.binding == HotkeyBinding(keyCode: 53, modifiers: [.command]))
    }

    @Test("ignores keystrokes while it is not listening")
    func ignoresStrayKeystrokes() {
        var recorder = SettingsShortcutRecorder(binding: .optionSpace)
        #expect(recorder.record(keyCode: 40, modifiers: [.command]) == .ignored)
        #expect(recorder.binding == .optionSpace)
    }

    @Test("cancelling clears both the listening state and the last refusal")
    func cancellingClearsEverything() {
        var recorder = SettingsShortcutRecorder(binding: .optionSpace)
        recorder.beginRecording()
        _ = recorder.record(keyCode: 40, modifiers: [])
        recorder.cancel()
        #expect(!recorder.isRecording)
        #expect(recorder.rejection == nil)
    }

    @Test("beginning again clears the refusal left over from last time")
    func beginningClearsTheLastRefusal() {
        var recorder = SettingsShortcutRecorder(binding: .optionSpace)
        recorder.beginRecording()
        _ = recorder.record(keyCode: 40, modifiers: [])
        recorder.beginRecording()
        #expect(recorder.rejection == nil)
    }

    @Test("replaces a stored shortcut that could never have worked")
    func repairsAnUnusableStoredShortcut() {
        let recorder = SettingsShortcutRecorder(
            binding: HotkeyBinding(keyCode: 0x90, modifiers: []))
        #expect(recorder.binding == .optionSpace)
        #expect(recorder.binding.isDeliverable)
    }
}
