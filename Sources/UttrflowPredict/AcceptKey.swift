/// Which key takes a suggestion, which cannot be Tab everywhere. See `Docs/predict-accept.md`.
public enum AcceptKey: String, Sendable, Equatable, CaseIterable, Codable {
    /// The default, and what Tab already means in a plain text field.
    case tab
    /// Terminals, where Tab is the shell's own completion and taking it would break it.
    case rightArrow
    /// Editors, where Tab indents and the language server's completion is already on it.
    case optionTab

    /// The keystroke that presses it.
    public var stroke: KeyStroke {
        switch self {
        case .tab: KeyStroke(.tab)
        case .rightArrow: KeyStroke(.rightArrow)
        case .optionTab: KeyStroke(.tab, modifiers: .option)
        }
    }
}

/// Which key accepts in which application, with whatever the user chose on top.
public struct AcceptKeys: Sendable, Equatable {
    /// What the user chose for one application, keyed by a lowercased bundle identifier.
    private let overrides: [String: AcceptKey]

    /// The shipped answer, which is the kind of application and nothing else.
    public static let standard = AcceptKeys()

    public init(overrides: [String: AcceptKey] = [:]) {
        self.overrides = overrides.reduce(into: [:]) { $0[$1.key.lowercased()] = $1.value }
    }

    /// The key that accepts in this application.
    public func key(forBundleIdentifier bundleIdentifier: String) -> AcceptKey {
        let identifier = bundleIdentifier.lowercased()
        if let chosen = overrides[identifier] { return chosen }
        if Self.terminals.contains(where: identifier.hasPrefix) { return .rightArrow }
        if Self.editors.contains(where: identifier.hasPrefix) { return .optionTab }
        return .tab
    }

    /// The same answer for a field, which is what the rest of the module carries around.
    public func key(for surface: Surface) -> AcceptKey {
        key(forBundleIdentifier: surface.bundleIdentifier)
    }

    /// Matched on a lowercased prefix, so one entry covers a vendor's whole family.
    private static let terminals = [
        "com.apple.terminal",
        "com.googlecode.iterm2",
        "com.mitchellh.ghostty",
        "net.kovidgoyal.kitty",
        "io.alacritty",
        "com.github.wez.wezterm",
        "dev.warp.warp",
        "co.zeit.hyper",
        "org.tabby",
    ]

    /// The same, for editors, where Tab is indentation before it is anything else.
    private static let editors = [
        "com.apple.dt.xcode",
        "com.microsoft.vscode",
        "com.visualstudio.code",
        "com.todesktop.230313mzl4w4u92",
        "com.jetbrains",
        "com.sublimetext",
        "dev.zed.zed",
        "org.vim.macvim",
        "com.panic.nova",
    ]
}
