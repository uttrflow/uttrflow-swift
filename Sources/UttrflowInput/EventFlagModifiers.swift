import CoreGraphics

internal import UttrflowCore
internal import UttrflowPredict

extension HotkeyModifier {
    /// The window server's flag that means this modifier is held.
    var eventFlag: CGEventFlags {
        switch self {
        case .command: .maskCommand
        case .option: .maskAlternate
        case .control: .maskControl
        case .shift: .maskShift
        }
    }

    /// The modifiers the flags hold, in declaration order; the one decoding of flags into modifiers.
    static func held(in flags: CGEventFlags) -> [HotkeyModifier] {
        allCases.filter { flags.contains($0.eventFlag) }
    }
}

extension KeyModifiers {
    /// The window server's flags, narrowed to the four that change what a key means.
    init(_ flags: CGEventFlags) {
        var modifiers = KeyModifiers()
        for modifier in HotkeyModifier.held(in: flags) {
            switch modifier {
            case .command: modifiers.insert(.command)
            case .option: modifiers.insert(.option)
            case .control: modifiers.insert(.control)
            case .shift: modifiers.insert(.shift)
            }
        }
        self = modifiers
    }
}
