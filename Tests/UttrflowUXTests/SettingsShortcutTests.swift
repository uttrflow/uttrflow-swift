// Tests for drawing a shortcut on keycaps and for recording a new one.
import UttrflowCore
import Testing

@testable import UttrflowUX

@Suite("Drawing a shortcut on keycaps")
struct SettingsShortcutDrawingTests {
    @Test("speaks the human shortcut name and spells modifier keys")
    func accessibilityLabelNamesBoundShortcut() {
        let keys = SettingsShortcut.keycaps(for: .controlCommandV)
        #expect(
            SettingsShortcut.accessibilityLabel(
                for: .pasteLastTranscript, keys: keys, isRecording: false)
                == "Paste last transcript shortcut, Control Command V")
    }

    @Test("says none when a shortcut has no keys")
    func accessibilityLabelNamesEmptyShortcut() {
        #expect(
            SettingsShortcut.accessibilityLabel(
                for: .copyLastTranscript, keys: [], isRecording: false)
                == "Copy last transcript shortcut, none")
    }

    @Test("explains that recording is listening and Escape cancels")
    func accessibilityLabelExplainsRecording() {
        let keys = SettingsShortcut.keycaps(for: .optionSpace)
        #expect(
            SettingsShortcut.accessibilityLabel(
                for: .dictate, keys: keys, isRecording: true)
                == "Dictate shortcut, Option Space, press the new shortcut, or Escape to cancel")
    }

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

    /// A chord of modifiers stored under one of its own keys, and the caps it draws as.
    struct ModifierChord: Sendable, CustomTestStringConvertible {
        let keyCode: UInt16
        let modifiers: Set<HotkeyModifier>
        let drawn: [String]
        var testDescription: String { "key \(keyCode) drawn as \(drawn.joined())" }
    }

    static let modifierChords: [ModifierChord] = [
        ModifierChord(keyCode: 58, modifiers: [.option, .command, .control], drawn: ["⌃", "⌥", "⌘"]),
        ModifierChord(keyCode: 61, modifiers: [.option, .control], drawn: ["⌃", "⌥"]),
        ModifierChord(keyCode: 55, modifiers: [.command, .shift], drawn: ["⇧", "⌘"]),
        ModifierChord(
            keyCode: 54, modifiers: [.command, .option, .shift, .control], drawn: ["⌃", "⌥", "⇧", "⌘"]),
        ModifierChord(keyCode: 59, modifiers: [.control, .option], drawn: ["⌃", "⌥"]),
        ModifierChord(keyCode: 62, modifiers: [.control, .command], drawn: ["⌃", "⌘"]),
        ModifierChord(keyCode: 56, modifiers: [.shift, .option], drawn: ["⌥", "⇧"]),
        ModifierChord(keyCode: 60, modifiers: [.shift, .control], drawn: ["⌃", "⇧"]),
    ]

    /// Issue 353: a chord of modifiers drew only the key it was stored under, so ⌃⌥⌘ read as ⌥.
    @Test(
        "draws every modifier of a chord made only of modifiers, each once and in order",
        arguments: modifierChords)
    func drawsAModifierChord(chord: ModifierChord) {
        let binding = HotkeyBinding(keyCode: chord.keyCode, modifiers: chord.modifiers)
        #expect(SettingsShortcut.keycaps(for: binding) == chord.drawn)
        #expect(SettingsShortcut.compact(binding) == chord.drawn.joined())
    }

    @Test("draws a chord's key modifier even when the stored set leaves it out")
    func drawsTheKeysOwnModifier() {
        let binding = HotkeyBinding(keyCode: 58, modifiers: [.control, .command])
        #expect(SettingsShortcut.keycaps(for: binding) == ["⌃", "⌥", "⌘"])
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
        #expect(outcome == .recorded(.shortcut(.dictate, expected)))
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
        #expect(change == .shortcut(.dictate, .functionHold))
        #expect(recorder.binding == .functionHold)
        #expect(!recorder.isRecording, "a recorded shortcut ends the recording")
        #expect(SettingsShortcut.compact(.functionHold) == "fn")
    }

    /// A chord of modifiers is matched by equality, so ⌃⌥ held does not fire on the way to a ⌃⌥ shortcut's key.
    @Test("accepts any combination of modifiers held together")
    func heldModifiersAreAccepted() {
        for (keyCode, modifiers) in [
            // The combination this was all about.
            (UInt16(58), Set<HotkeyModifier>([.control, .option])),
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

    /// Issue 1207: Carbon cannot arm a claimed action with a held-modifier-only combination, so the recorder refuses it too.
    @Test("refuses a held modifier combination for a claimed action and keeps the previous shortcut")
    func heldModifiersAreRefusedForAClaimedAction() {
        for action: ShortcutAction in [.clipboard, .pasteLastTranscript, .copyLastTranscript] {
            var recorder = SettingsShortcutRecorder(binding: .optionSpace, action: action)
            recorder.beginRecording()
            let outcome = recorder.record(keyCode: 58, modifiers: [.control, .option])

            #expect(
                outcome == .refused(SettingsRejection(reason: SettingsEditor.heldChordNotClaimable)),
                "\(action)")
            #expect(recorder.binding == .optionSpace, "\(action)")
            #expect(recorder.isRecording, "\(action)")
        }
    }

    /// Issue 342: one of these alone is part of every shortcut that uses it, so the field refuses it and keeps listening.
    @Test("refuses a modifier pressed on its own and keeps the previous shortcut")
    func bareModifiersAreRefused() {
        for (keyCode, modifiers) in [
            (UInt16(55), Set<HotkeyModifier>([.command])), (UInt16(58), Set([.option])),
            (UInt16(59), Set([.control])), (UInt16(56), Set([.shift])), (UInt16(61), Set()),
        ] {
            var recorder = SettingsShortcutRecorder(binding: .optionSpace)
            recorder.beginRecording()
            let outcome = recorder.record(keyCode: keyCode, modifiers: modifiers)

            #expect(outcome == .refused(SettingsRejection(reason: SettingsEditor.bareModifier)), "\(keyCode)")
            #expect(recorder.binding == .optionSpace)
            #expect(recorder.isRecording)
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

    /// Driven the way the field drives it: whole keystrokes, not hand-picked calls.
    @Suite("Every shape, as keystrokes")
    struct Strokes {
        private func held(_ mods: Set<HotkeyModifier>, fn: Bool = false, key: UInt16 = 0) -> KeyStroke {
            KeyStroke(
                keyCode: key, modifiers: mods, isFunctionDown: fn, phase: .modifiersChanged,
                isKeyDown: true)
        }
        private func lifted(_ mods: Set<HotkeyModifier>, key: UInt16) -> KeyStroke {
            KeyStroke(keyCode: key, modifiers: mods, phase: .modifiersChanged, isKeyDown: false)
        }
        private func down(_ key: UInt16, _ mods: Set<HotkeyModifier>) -> KeyStroke {
            KeyStroke(keyCode: key, modifiers: mods, phase: .down)
        }
        private func recorder() -> SettingsShortcutRecorder {
            var r = SettingsShortcutRecorder(binding: .optionSpace)
            r.beginRecording()
            return r
        }

        @Test("single Fn")
        func singleFn() {
            var r = recorder()
            _ = r.receive(held([], fn: true, key: 63))
            _ = r.receive(held([]))
            #expect(r.binding == .functionHold)
        }

        @Test("single modifier held alone is refused")
        func singleModifier() {
            var r = recorder()
            _ = r.receive(held([.command], key: 55))
            _ = r.receive(held([]))
            #expect(r.binding == .optionSpace)
            #expect(r.rejection == SettingsEditor.bareModifier)
        }

        @Test("a modifier let go never becomes the shortcut")
        func liftedModifierIsNotTheShortcut() {
            var r = recorder()
            // ⌘ down, ⌥ down, ⌥ up, ⌘ up: the pair held together is the shortcut.
            _ = r.receive(held([.command], key: 55))
            _ = r.receive(held([.command, .option], key: 58))
            _ = r.receive(lifted([.command], key: 58))
            _ = r.receive(held([]))
            #expect(r.binding == HotkeyBinding(keyCode: 58, modifiers: [.command, .option]))
            #expect(r.binding.isCoherent)
        }

        @Test("what is recorded always names a key its modifiers contain")
        func everyRecordingIsCoherent() {
            for last in [UInt16(55), 56, 58, 59, 63] {
                var r = recorder()
                _ = r.receive(held([.control], key: 59))
                _ = r.receive(lifted([.control], key: last))
                _ = r.receive(held([]))
                #expect(r.binding.isCoherent, "key \(last) left an incoherent binding")
            }
        }

        @Test("two keys, a modifier and a key")
        func twoKeys() {
            var r = recorder()
            _ = r.receive(held([.option], key: 58))
            _ = r.receive(down(49, [.option]))
            #expect(r.binding == .optionSpace)
            // The modifier let go afterwards must not overwrite what was recorded.
            _ = r.receive(held([]))
            #expect(r.binding == .optionSpace)
        }

        @Test("three keys, two modifiers and a key")
        func threeKeys() {
            var r = recorder()
            _ = r.receive(held([.command], key: 55))
            _ = r.receive(held([.command, .shift], key: 56))
            _ = r.receive(down(0, [.command, .shift]))
            #expect(r.binding == HotkeyBinding(keyCode: 0, modifiers: [.command, .shift]))
        }

        @Test("two modifiers held together, with no key against them")
        func twoModifiers() {
            var r = recorder()
            _ = r.receive(held([.control], key: 59))
            _ = r.receive(held([.control, .option], key: 58))
            _ = r.receive(held([]))
            #expect(r.binding == HotkeyBinding(keyCode: 58, modifiers: [.control, .option]))
        }

        @Test("three modifiers held together")
        func threeModifiers() {
            var r = recorder()
            _ = r.receive(held([.control], key: 59))
            _ = r.receive(held([.control, .option], key: 58))
            _ = r.receive(held([.control, .option, .shift], key: 56))
            _ = r.receive(held([]))
            #expect(r.binding == HotkeyBinding(keyCode: 56, modifiers: [.control, .option, .shift]))
        }

        @Test("a key coming up is not a shortcut")
        func keyUpIsQuiet() {
            var r = recorder()
            #expect(r.receive(KeyStroke(keyCode: 49, phase: .up)) == .ignored)
            #expect(r.isRecording)
        }

        @Test("nothing is taken before the field is listening")
        func quietUntilRecording() {
            var r = SettingsShortcutRecorder(binding: .optionSpace)
            #expect(r.receive(held([], fn: true, key: 63)) == .ignored)
            #expect(r.binding == .optionSpace)
        }
    }

    /// Every shape of shortcut the field has to take, which is what kept breaking one at a time.
    @Suite("Every shape of shortcut")
    struct Shapes {
        /// Fn held on its own, the shipping default.
        @Test("single Fn")
        func singleFn() {
            var r = SettingsShortcutRecorder(binding: .optionSpace)
            r.beginRecording()
            _ = r.hold(keyCode: 63, modifiers: [])
            #expect(r.release() == .recorded(.shortcut(.dictate, .functionHold)))
            #expect(r.binding == .functionHold)
        }

        /// One modifier held on its own is part of every shortcut using it, so it is the one shape refused.
        @Test("single modifier held alone is refused")
        func singleModifier() {
            var r = SettingsShortcutRecorder(binding: .functionHold)
            r.beginRecording()
            _ = r.hold(keyCode: 55, modifiers: [.command])
            #expect(r.release() == .refused(SettingsRejection(reason: SettingsEditor.bareModifier)))
            #expect(r.binding == .functionHold)
        }

        /// One modifier and one key: the combination that could not be typed at all.
        @Test("two keys, a modifier and a key")
        func twoKeys() {
            var r = SettingsShortcutRecorder(binding: .functionHold)
            r.beginRecording()
            _ = r.hold(keyCode: 58, modifiers: [.option])
            #expect(
                r.record(keyCode: 49, modifiers: [.option]) == .recorded(.shortcut(.dictate, .optionSpace)))
            #expect(r.binding == .optionSpace)
            // The modifier coming up afterwards must not overwrite what was just recorded.
            #expect(r.release() == .ignored)
            #expect(r.binding == .optionSpace)
        }

        /// Two modifiers and a key, pressed in the order a hand presses them.
        @Test("three keys, two modifiers and a key")
        func threeKeys() {
            var r = SettingsShortcutRecorder(binding: .functionHold)
            r.beginRecording()
            _ = r.hold(keyCode: 55, modifiers: [.command])
            _ = r.hold(keyCode: 56, modifiers: [.command, .shift])
            let wanted = HotkeyBinding(keyCode: 0, modifiers: [.command, .shift])
            #expect(
                r.record(keyCode: 0, modifiers: [.command, .shift]) == .recorded(.shortcut(.dictate, wanted)))
            #expect(r.binding == wanted)
        }

        /// Two modifiers held together and let go: the pair, not whichever was pressed last.
        @Test("two modifiers held together, with no key against them")
        func twoModifiersHeld() {
            var r = SettingsShortcutRecorder(binding: .functionHold)
            r.beginRecording()
            _ = r.hold(keyCode: 59, modifiers: [.control])
            _ = r.hold(keyCode: 58, modifiers: [.control, .option])
            let wanted = HotkeyBinding(keyCode: 58, modifiers: [.control, .option])
            #expect(r.release() == .recorded(.shortcut(.dictate, wanted)))
            #expect(r.binding == wanted)
        }

        /// Three modifiers held together, the widest hold the field allows.
        @Test("three modifiers held together")
        func threeModifiersHeld() {
            var r = SettingsShortcutRecorder(binding: .functionHold)
            r.beginRecording()
            _ = r.hold(keyCode: 59, modifiers: [.control])
            _ = r.hold(keyCode: 58, modifiers: [.control, .option])
            _ = r.hold(keyCode: 56, modifiers: [.control, .option, .shift])
            let wanted = HotkeyBinding(keyCode: 56, modifiers: [.control, .option, .shift])
            #expect(r.release() == .recorded(.shortcut(.dictate, wanted)))
        }

        @Test("a release with nothing held changes nothing")
        func releaseWithoutHold() {
            var r = SettingsShortcutRecorder(binding: .optionSpace)
            r.beginRecording()
            #expect(r.release() == .ignored)
            #expect(r.binding == .optionSpace)
            #expect(r.isRecording)
        }
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
