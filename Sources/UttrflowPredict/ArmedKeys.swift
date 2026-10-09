public import UttrflowCore

/// The keystrokes the tap is swallowing right now, packed small enough for one atomic read.
public struct ArmedKeys: OptionSet, Sendable, Equatable {
    /// One bit per slot the tap is swallowing.
    public let rawValue: UInt32

    /// The set those bits stand for.
    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    /// Tab on its own.
    public static let tab = ArmedKeys(rawValue: 1 << 0)
    /// ⌥Tab, which is how an editor accepts.
    public static let optionTab = ArmedKeys(rawValue: 1 << 1)
    /// The right arrow, which is how a terminal accepts.
    public static let rightArrow = ArmedKeys(rawValue: 1 << 2)
    /// Return, claimed only while a list is being walked.
    public static let `return` = ArmedKeys(rawValue: 1 << 3)
    /// Escape, which minimises and then silences.
    public static let escape = ArmedKeys(rawValue: 1 << 4)
    /// ⌥Escape, which turns the feature off everywhere.
    public static let optionEscape = ArmedKeys(rawValue: 1 << 5)
    /// ⌥↓, which opens the list and walks it; a bare ↓ is always the application's.
    public static let optionDownArrow = ArmedKeys(rawValue: 1 << 6)
    /// ⌥↑, claimed only once the list has been walked; a bare ↑ is always the application's.
    public static let optionUpArrow = ArmedKeys(rawValue: 1 << 7)

    /// Every slot with the keystroke that fills it, so arming can be derived from the decision itself.
    public static let slots: [(stroke: KeyStroke, slot: ArmedKeys)] = [
        (KeyStroke(.tab), .tab),
        (KeyStroke(.tab, modifiers: .option), .optionTab),
        (KeyStroke(.rightArrow), .rightArrow),
        (KeyStroke(.return), .return),
        (KeyStroke(.escape), .escape),
        (KeyStroke(.escape, modifiers: .option), .optionEscape),
        (KeyStroke(.downArrow, modifiers: .option), .optionDownArrow),
        (KeyStroke(.upArrow, modifiers: .option), .optionUpArrow),
    ]

    /// The one slot a keystroke occupies, in integer work only because the tap's callback may not allocate.
    public static func slot(of stroke: KeyStroke) -> ArmedKeys {
        if stroke.modifiers == .option {
            switch stroke.key {
            case .tab: return .optionTab
            case .escape: return .optionEscape
            case .downArrow: return .optionDownArrow
            case .upArrow: return .optionUpArrow
            default: return []
            }
        }
        guard stroke.modifiers.isEmpty else { return [] }
        switch stroke.key {
        case .tab: return .tab
        case .rightArrow: return .rightArrow
        case .return: return .return
        case .escape: return .escape
        case .downArrow, .upArrow, .other: return []
        }
    }

    /// The keystroke a single slot stands for, so a caught bit can be reported as a key.
    public static func stroke(of slot: ArmedKeys) -> KeyStroke? {
        slots.first { $0.slot == slot }?.stroke
    }
}
