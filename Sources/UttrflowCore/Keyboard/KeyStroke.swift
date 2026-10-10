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

    /// The hardware key code that presses this key again, or nil for a key this feature never takes.
    public var keyCode: UInt16? {
        switch self {
        case .tab: 48
        case .return: 36
        case .escape: 53
        case .rightArrow: 124
        case .downArrow: 125
        case .upArrow: 126
        case .other: nil
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
