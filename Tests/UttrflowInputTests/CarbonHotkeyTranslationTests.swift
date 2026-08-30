import Testing

@testable import UttrflowCore
@testable import UttrflowInput

/// Carbon's own modifier bitmask, verified against the constants in `HIToolbox` on this
/// machine. Written out rather than imported so that a change to what we send Carbon
/// has to be a deliberate edit to a number, not a silent follow-along.
private enum CarbonBit {
    static let command: UInt32 = 256
    static let shift: UInt32 = 512
    static let option: UInt32 = 2048
    static let control: UInt32 = 4096
}

/// Key codes Carbon accepts and then never delivers on, which is why translation
/// rejects them first.
private enum CarbonUnusableKeyCode {
    static let leftOption: UInt16 = 58
    static let capsLock: UInt16 = 57
    static let rightCommand: UInt16 = 54
    static let beyondVirtualKeyRange: UInt16 = 300
}

@Suite("CarbonHotkey translation")
struct CarbonHotkeyTranslationTests {
    @Test(
        "maps each modifier to its Carbon bit",
        arguments: [
            (HotkeyModifier.command, CarbonBit.command),
            (HotkeyModifier.shift, CarbonBit.shift),
            (HotkeyModifier.option, CarbonBit.option),
            (HotkeyModifier.control, CarbonBit.control),
        ]
    )
    func mapsEachModifier(modifier: HotkeyModifier, bit: UInt32) throws {
        let hotkey = try CarbonHotkey(binding: HotkeyBinding(keyCode: 49, modifiers: [modifier]))

        #expect(hotkey.modifierMask == bit)
    }

    @Test("covers every modifier the product offers")
    func mapsEveryModifier() throws {
        for modifier in HotkeyModifier.allCases {
            let hotkey = try CarbonHotkey(binding: HotkeyBinding(keyCode: 49, modifiers: [modifier]))
            #expect(hotkey.modifierMask != 0, "\(modifier) produced no Carbon bit")
        }
    }

    @Test("ORs a combination into one mask")
    func combinesModifiers() throws {
        let twoKeys = try CarbonHotkey(
            binding: HotkeyBinding(keyCode: 49, modifiers: [.command, .shift]))
        let everything = try CarbonHotkey(
            binding: HotkeyBinding(keyCode: 49, modifiers: [.command, .shift, .option, .control]))

        #expect(twoKeys.modifierMask == CarbonBit.command | CarbonBit.shift)
        #expect(
            everything.modifierMask
                == CarbonBit.command | CarbonBit.shift | CarbonBit.option | CarbonBit.control)
    }

    /// The shortcut the product ships with, spelled out because everything else in the
    /// hotkey path is only as right as this one case.
    @Test("translates Option+Space")
    func translatesOptionSpace() throws {
        let hotkey = try CarbonHotkey(binding: .optionSpace)
        let spelledOut = try CarbonHotkey(binding: HotkeyBinding(keyCode: 49, modifiers: [.option]))

        #expect(hotkey.keyCode == 49)
        #expect(hotkey.modifierMask == CarbonBit.option)
        #expect(hotkey == spelledOut)
    }

    @Test("keeps the key code Carbon needs, unchanged")
    func keepsKeyCode() throws {
        let hotkey = try CarbonHotkey(binding: HotkeyBinding(keyCode: 8, modifiers: [.command]))

        #expect(hotkey.keyCode == 8)
    }

    @Test("takes the highest key code a keyboard can produce")
    func acceptsHighestKeyCode() throws {
        let hotkey = try CarbonHotkey(
            binding: HotkeyBinding(keyCode: CarbonHotkey.highestKeyCode, modifiers: [.control]))

        #expect(hotkey.keyCode == UInt32(CarbonHotkey.highestKeyCode))
    }

    @Test("refuses a shortcut with no modifier")
    func rejectsBareKey() {
        #expect(throws: CarbonHotkeyRejection.noModifiers) {
            try CarbonHotkey(binding: HotkeyBinding(keyCode: 49, modifiers: []))
        }
    }

    @Test(
        "refuses a modifier key as the shortcut key",
        arguments: [
            CarbonUnusableKeyCode.leftOption,
            CarbonUnusableKeyCode.capsLock,
            CarbonUnusableKeyCode.rightCommand,
        ]
    )
    func rejectsModifierOnlyShortcut(keyCode: UInt16) {
        #expect(throws: CarbonHotkeyRejection.modifierUsedAsKey(keyCode: keyCode)) {
            try CarbonHotkey(binding: HotkeyBinding(keyCode: keyCode, modifiers: [.option]))
        }
    }

    @Test("refuses a key code no keyboard can send")
    func rejectsOutOfRangeKeyCode() {
        let keyCode = CarbonUnusableKeyCode.beyondVirtualKeyRange
        #expect(throws: CarbonHotkeyRejection.keyCodeOutOfRange(keyCode: keyCode)) {
            try CarbonHotkey(binding: HotkeyBinding(keyCode: keyCode, modifiers: [.command]))
        }
    }

    /// A rejection that does not say what is wrong would reach the user as a shortcut
    /// that simply does nothing, which is the failure this whole type exists to prevent.
    @Test(
        "says why it refused",
        arguments: [
            CarbonHotkeyRejection.noModifiers,
            CarbonHotkeyRejection.modifierUsedAsKey(keyCode: CarbonUnusableKeyCode.leftOption),
            CarbonHotkeyRejection.keyCodeOutOfRange(
                keyCode: CarbonUnusableKeyCode.beyondVirtualKeyRange),
        ]
    )
    func explainsRejection(rejection: CarbonHotkeyRejection) {
        #expect(rejection.reason.count > 20, "not much of an explanation: \(rejection.reason)")
        #expect(rejection.reason.hasSuffix("."))
    }

    /// ``HotkeyBinding/isDeliverable`` restates these rules in a module that cannot
    /// import the platform headers, so the two can drift apart. Nothing else would
    /// notice: the settings store would keep a shortcut the monitor then refuses, or
    /// throw away one that would have worked. This is the test that stops it.
    ///
    /// **Two delivery paths, so two invariants.** A binding whose key is an ordinary one
    /// is registered with the window server, and there the two verdicts must agree
    /// exactly. A binding whose key is a modifier is a *hold*, watched through flag
    /// changes by ``HeldModifierMonitor`` — Carbon refuses those and always did, which is
    /// the whole reason that monitor exists. Asserting agreement across both would assert
    /// that holds do not work.
    @Test("agrees with the binding's own verdict for every key a keyboard can send")
    func deliverabilityMatchesTranslation() {
        for keyCode in UInt16(0)...UInt16(300) {
            let binding = HotkeyBinding(keyCode: keyCode, modifiers: [.command])
            guard binding.heldModifier == nil else { continue }
            let translates = (try? CarbonHotkey(binding: binding)) != nil

            #expect(binding.isDeliverable == translates, "disagreed about key code \(keyCode)")
        }
    }

    /// The other half, and the one that says why holds need their own monitor: Carbon
    /// refuses every one of them. If this ever started passing, `HeldModifierMonitor`
    /// would be redundant — and far more likely, something has broken.
    @Test("refuses every held-modifier binding, which is why they are watched instead")
    func holdsAreNeverCarbonRegistrable() {
        for keyCode in HotkeyBinding.modifierKeyCodes.sorted() {
            let binding = HotkeyBinding(keyCode: keyCode, modifiers: [.command])
            #expect(binding.heldModifier != nil, "key \(keyCode) should be a hold")
            #expect(
                (try? CarbonHotkey(binding: binding)) == nil,
                "Carbon accepted key code \(keyCode); it has never fired one")
        }
    }

    @Test("agrees that a shortcut with no modifier cannot be delivered")
    func deliverabilityMatchesTranslationWithoutModifiers() {
        let binding = HotkeyBinding(keyCode: 49, modifiers: [])

        #expect(!binding.isDeliverable)
        #expect((try? CarbonHotkey(binding: binding)) == nil)
    }

    @Test("names the modifier requirement, the offending key, and the range")
    func rejectionsNameTheProblem() {
        let leftOption = CarbonUnusableKeyCode.leftOption
        let tooHigh = CarbonUnusableKeyCode.beyondVirtualKeyRange

        #expect(CarbonHotkeyRejection.noModifiers.reason.contains("modifier"))
        #expect(
            CarbonHotkeyRejection.modifierUsedAsKey(keyCode: leftOption).reason
                .contains("\(leftOption)"))
        #expect(
            CarbonHotkeyRejection.keyCodeOutOfRange(keyCode: tooHigh).reason.contains("\(tooHigh)"))
        #expect(
            CarbonHotkeyRejection.keyCodeOutOfRange(keyCode: tooHigh).reason
                .contains("\(CarbonHotkey.highestKeyCode)"))
    }
}

/// What can be said about the monitor without asking the window server for a real,
/// system-wide shortcut — which is to say, the refusals. Everything here stops short of
/// ``CarbonHotkeyMonitor`` reaching Carbon at all.
@Suite("CarbonHotkeyMonitor refusals")
struct CarbonHotkeyMonitorTests {
    /// The defect these cover: each of these bindings used to trap in a debug build and
    /// do nothing at all in a release one, leaving a user with a shortcut that never
    /// fired and no explanation.
    @Test(
        "refuses a shortcut it cannot watch for, rather than failing silently",
        arguments: [
            HotkeyBinding(keyCode: 49, modifiers: []),
            HotkeyBinding(keyCode: CarbonUnusableKeyCode.beyondVirtualKeyRange, modifiers: [.command]),
            HotkeyBinding(keyCode: CarbonUnusableKeyCode.leftOption, modifiers: [.option]),
        ]
    )
    @MainActor
    func refusesUnusableBinding(binding: HotkeyBinding) {
        let monitor = CarbonHotkeyMonitor()
        defer { monitor.stop() }

        #expect(throws: HotkeyError.shortcutUnavailable) {
            try monitor.start(binding: binding)
        }
    }

    @Test("stops without complaint when it was never started")
    @MainActor
    func stopsWithoutStarting() {
        CarbonHotkeyMonitor().stop()
    }
}

/// Spelled out rather than derived from `CaseIterable`, so that adding a case to the
/// error obliges someone to write the sentence a user will read for it.
private let everyHotkeyError: [HotkeyError] = [.observationNotPermitted, .shortcutUnavailable]

/// The refusal is only worth throwing if what reaches the user says something. These
/// two sentences are the whole of what they will see.
@Suite("HotkeyError")
struct HotkeyErrorTests {
    @Test("offers System Settings only for the failure System Settings can fix")
    func recoveries() {
        #expect(HotkeyError.observationNotPermitted.recovery == .openSystemSettings(.accessibility))
        #expect(HotkeyError.shortcutUnavailable.recovery == .retry)
    }

    @Test("says what went wrong in a finished sentence", arguments: everyHotkeyError)
    func messages(error: HotkeyError) {
        #expect(error.userMessage.count > 20, "not much of an explanation: \(error.userMessage)")
        #expect(error.userMessage.hasSuffix("."))
        #expect(error.userMessage.first?.isUppercase == true)
    }

    /// A message naming Carbon, a key code or a registration would tell the user
    /// something about our code rather than about their Mac.
    @Test("keeps the implementation out of what the user reads")
    func messagesNameNoImplementation() {
        let forbidden = ["Carbon", "hot key", "hotkey", "register", "key code", "OSStatus"]
        for error in everyHotkeyError {
            let message = error.userMessage.lowercased()
            for word in forbidden {
                #expect(!message.contains(word.lowercased()), "\(error) leaks \"\(word)\"")
            }
        }
    }

    @Test("tells the user which shortcut problem they have")
    func messagesDistinguishTheCases() {
        #expect(HotkeyError.observationNotPermitted.userMessage.contains("System Settings"))
        #expect(HotkeyError.shortcutUnavailable.userMessage.contains("another app"))
    }
}
