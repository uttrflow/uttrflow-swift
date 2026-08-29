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

    @Test("shows a key it has no name for as its code rather than as nothing")
    func namesTheUnnameable() {
        #expect(SettingsShortcut.name(of: 200) == "Key 200")
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
        // Still listening: the user is one keystroke from a shortcut that works, rather
        // than having to reopen the field to try again.
        #expect(recorder.isRecording)
    }

    /// The complaint this answers was "I am not able to register the custom keys".
    ///
    /// Nothing was broken about recording: a modifier pressed on its own sends only
    /// `.flagsChanged`, the field listened for `.keyDown` alone, and so the most natural
    /// thing to try on a dictation app — bind ⌘, or Fn, the way other dictation apps do —
    /// produced no shortcut, no refusal and no message. The field said "Press the new
    /// shortcut" for as long as you cared to look at it.
    ///
    /// Such a binding really is undeliverable: the window server accepts a modifier held
    /// alone and then never fires it. So it stays refused. What changed is that the
    /// refusal now reaches the person, and says which key would work instead.
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

    @Test("refuses a modifier pressed on its own, and says so rather than saying nothing")
    func modifierAloneIsRefusedOutLoud() {
        // Left command, held with its own flag — exactly what `.flagsChanged` reports.
        for (keyCode, modifier) in [
            (UInt16(55), HotkeyModifier.command),
            (UInt16(58), HotkeyModifier.option),
            (UInt16(59), HotkeyModifier.control),
            (UInt16(56), HotkeyModifier.shift),
        ] {
            var recorder = SettingsShortcutRecorder(binding: .optionSpace)
            recorder.beginRecording()
            let outcome = recorder.record(keyCode: keyCode, modifiers: [modifier])

            guard case .refused(let rejection) = outcome else {
                Issue.record("\(modifier) on its own was accepted as a shortcut")
                return
            }
            // Not the "hold a modifier as well" sentence: they held one. The useful
            // thing to say is which key is missing.
            #expect(rejection.reason.contains("letter"))
            #expect(recorder.binding == .optionSpace)
            #expect(recorder.isRecording, "still listening, so the next press can succeed")
        }
    }

    @Test("a refusal followed by a good combination ends with the good one")
    func recoversFromARefusal() {
        var recorder = SettingsShortcutRecorder(binding: .optionSpace)
        recorder.beginRecording()
        _ = recorder.record(keyCode: 58, modifiers: [.option])
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
