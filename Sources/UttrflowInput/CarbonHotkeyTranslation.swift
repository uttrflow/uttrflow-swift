private import Carbon
public import UttrflowCore

/// Why a binding cannot become a Carbon hot key.
///
/// Carbon has no opinion about any of these: `RegisterEventHotKey` was measured
/// returning `noErr` for a shortcut with no modifiers, for a key code far outside the
/// virtual key range, and for a modifier key used as the shortcut key. Each one then
/// never fires. Every check that keeps that from happening has to be ours.
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

/// A shortcut in the shape `RegisterEventHotKey` takes it: a virtual key code and a
/// bitmask of Carbon's own modifier constants.
///
/// The only way to make one is through the initialiser below, so a value of this type
/// is a shortcut Carbon can actually deliver.
public struct CarbonHotkey: Sendable, Equatable {
    public let keyCode: UInt32
    public let modifierMask: UInt32

    /// Virtual key codes are 7-bit; anything above this came from somewhere other than
    /// a keyboard.
    static let highestKeyCode: UInt16 = 0x7F

    /// The keys that only ever modify another key. Held as codes rather than a range
    /// because the range they happen to occupy is a coincidence of the layout tables.
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

    /// Carbon's constants, not Cocoa's: `RegisterEventHotKey` predates
    /// `NSEvent.ModifierFlags` and takes the older bitmask.
    private static func carbonBit(for modifier: HotkeyModifier) -> UInt32 {
        switch modifier {
        case .command: UInt32(cmdKey)
        case .option: UInt32(optionKey)
        case .control: UInt32(controlKey)
        case .shift: UInt32(shiftKey)
        }
    }
}
