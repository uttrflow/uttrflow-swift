public import UttrflowCore

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

    /// The shipped answer with the user's own choices laid over it.
    public init(overrides: [String: AcceptKey] = [:]) {
        self.overrides = overrides.reduce(into: [:]) { $0[ApplicationKey.of($1.key)] = $1.value }
    }

    /// The key that accepts in this application.
    public func key(forBundleIdentifier bundleIdentifier: String) -> AcceptKey {
        key(for: AppContext(bundleIdentifier: bundleIdentifier))
    }

    /// The key that accepts in this application, including when a browser title identifies its destination.
    public func key(for application: AppContext) -> AcceptKey {
        let identifier = application.bundleIdentifier.map(ApplicationKey.of)
        if let identifier, let chosen = overrides[identifier] { return chosen }
        if let identifier, TerminalApplications.contains(identifier) { return .rightArrow }
        if let kind = DestinationClassifier.kind(for: application) {
            switch kind {
            case .codeEditor, .sqlEditor, .documentEditor, .spreadsheet, .notes:
                return .optionTab
            case .chat, .email, .terminal:
                return .tab
            }
        }
        return .tab
    }

    /// The same answer for a field, which is what the rest of the module carries around.
    public func key(for surface: Surface) -> AcceptKey {
        key(forBundleIdentifier: surface.bundleIdentifier)
    }
}
