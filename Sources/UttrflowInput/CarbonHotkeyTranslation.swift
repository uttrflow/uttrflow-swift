private import Carbon
public import UttrflowCore

/// Why a binding cannot become a Carbon hot key. See `Docs/core-hotkeys.md`.
public enum CarbonHotkeyRejection: Error, Sendable, Equatable {
    case noModifiers
    /// A modifier held down on its own — Carbon accepts the registration and stays silent.
    case modifierUsedAsKey(keyCode: UInt16)
    /// Outside the 7-bit space of hardware virtual key codes.
    case keyCodeOutOfRange(keyCode: UInt16)

    /// Said plainly enough to put in front of whoever chose the shortcut.
    public var reason: String {
        switch self {
        case .noModifiers:
            "A shortcut needs at least one modifier, or it would fire while typing."
        case .modifierUsedAsKey(let keyCode):
            "Key code \(keyCode) is a modifier key, which cannot be a shortcut's key."
        case .keyCodeOutOfRange(let keyCode):
            "Key code \(keyCode) is not a hardware key code; they run from 0 to \(CarbonHotkey.highestKeyCode)."
        }
    }
}

/// A shortcut Carbon can deliver: a virtual key code and a bitmask of its own modifier constants.
public struct CarbonHotkey: Sendable, Equatable {
    /// The virtual key code, in the width `RegisterEventHotKey` takes.
    public let keyCode: UInt32
    /// The modifiers as Carbon's own bits, ORed together.
    public let modifierMask: UInt32

    /// Virtual key codes are 7-bit; anything above this came from something other than a keyboard.
    static let highestKeyCode: UInt16 = 0x7F

    /// The keys that only ever modify another key, as codes rather than the range they occupy.
    private static let modifierKeyCodes: Set<UInt16> = [
        UInt16(kVK_Command), UInt16(kVK_RightCommand),
        UInt16(kVK_Shift), UInt16(kVK_RightShift),
        UInt16(kVK_Option), UInt16(kVK_RightOption),
        UInt16(kVK_Control), UInt16(kVK_RightControl),
        UInt16(kVK_CapsLock), UInt16(kVK_Function),
    ]

    public init(binding: HotkeyBinding) throws(CarbonHotkeyRejection) {
        guard binding.isUsable else { throw .noModifiers }
        guard binding.keyCode <= Self.highestKeyCode else {
            throw .keyCodeOutOfRange(keyCode: binding.keyCode)
        }
        guard !Self.modifierKeyCodes.contains(binding.keyCode) else {
            throw .modifierUsedAsKey(keyCode: binding.keyCode)
        }

        keyCode = UInt32(binding.keyCode)
        modifierMask = binding.modifiers.reduce(into: UInt32(0)) { mask, modifier in
            mask |= Self.carbonBit(for: modifier)
        }
    }

    /// Carbon's own constant for one modifier, which is not `NSEvent.ModifierFlags`.
    private static func carbonBit(for modifier: HotkeyModifier) -> UInt32 {
        switch modifier {
        case .command: UInt32(cmdKey)
        case .option: UInt32(optionKey)
        case .control: UInt32(controlKey)
        case .shift: UInt32(shiftKey)
        }
    }
}
