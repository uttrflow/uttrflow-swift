/// The modifiers a keystroke carries, named here so deciding stays free of AppKit.
public struct KeyModifiers: OptionSet, Sendable, Equatable {
    /// One bit per modifier held.
    public let rawValue: UInt8

    /// The set those bits stand for.
    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    /// ⌘, which every application claims for its own shortcuts.
    public static let command = KeyModifiers(rawValue: 1 << 0)
    /// ⌥, which is what an editor's accept key and the whole feature's off switch carry.
    public static let option = KeyModifiers(rawValue: 1 << 1)
    /// ⌃, which a terminal reads as a control character.
    public static let control = KeyModifiers(rawValue: 1 << 2)
    /// ⇧, which turns Tab into the application's own back-tab.
    public static let shift = KeyModifiers(rawValue: 1 << 3)
}

/// The keys this feature has an opinion about; every other key is ``other``.
public enum Key: Sendable, Equatable, CaseIterable {
    /// Tab, which accepts wherever nothing else has claimed it.
    case tab
    /// Return, which runs the command and sends the message.
    case `return`
    /// Escape, which is the whole dismissal ladder.
    case escape
    /// The right arrow, which accepts in a terminal.
    case rightArrow
    /// The down arrow, which opens and walks the list.
    case downArrow
    /// The up arrow, which walks back up it.
    case upArrow
    /// Every other key, which this feature has no opinion about.
    case other

    /// Hardware virtual key codes, which are positional and so hold on any keyboard layout.
    public init(keyCode: UInt16) {
        switch keyCode {
        case 48: self = .tab
        // 36 is Return and 76 is the keypad's Enter; both send a line in every app that takes one.
        case 36, 76: self = .return
        case 53: self = .escape
        case 124: self = .rightArrow
        case 125: self = .downArrow
        case 126: self = .upArrow
        default: self = .other
        }
    }
}

/// One keypress, reduced to what deciding needs.
public struct KeyStroke: Sendable, Equatable {
    /// Which key was pressed.
    public let key: Key
    /// What was held down with it.
    public let modifiers: KeyModifiers

    /// One keypress, named rather than coded.
    public init(_ key: Key, modifiers: KeyModifiers = []) {
        self.key = key
        self.modifiers = modifiers
    }

    /// The same stroke as the window server reports it.
    public init(keyCode: UInt16, modifiers: KeyModifiers = []) {
        self.init(Key(keyCode: keyCode), modifiers: modifiers)
    }
}

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
    /// The down arrow, which opens the list.
    public static let downArrow = ArmedKeys(rawValue: 1 << 6)
    /// The up arrow, claimed only once the list has been walked.
    public static let upArrow = ArmedKeys(rawValue: 1 << 7)

    /// Every slot with the keystroke that fills it, so arming can be derived from the decision itself.
    public static let slots: [(stroke: KeyStroke, slot: ArmedKeys)] = [
        (KeyStroke(.tab), .tab),
        (KeyStroke(.tab, modifiers: .option), .optionTab),
        (KeyStroke(.rightArrow), .rightArrow),
        (KeyStroke(.return), .return),
        (KeyStroke(.escape), .escape),
        (KeyStroke(.escape, modifiers: .option), .optionEscape),
        (KeyStroke(.downArrow), .downArrow),
        (KeyStroke(.upArrow), .upArrow),
    ]

    /// The one slot a keystroke occupies, in integer work only because the tap's callback may not allocate.
    public static func slot(of stroke: KeyStroke) -> ArmedKeys {
        if stroke.modifiers == .option {
            switch stroke.key {
            case .tab: return .optionTab
            case .escape: return .optionEscape
            default: return []
            }
        }
        guard stroke.modifiers.isEmpty else { return [] }
        switch stroke.key {
        case .tab: return .tab
        case .rightArrow: return .rightArrow
        case .return: return .return
        case .escape: return .escape
        case .downArrow: return .downArrow
        case .upArrow: return .upArrow
        case .other: return []
        }
    }

    /// The keystroke a single slot stands for, so a caught bit can be reported as a key.
    public static func stroke(of slot: ArmedKeys) -> KeyStroke? {
        slots.first { $0.slot == slot }?.stroke
    }
}
