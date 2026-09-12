/// The sort of app a row of the destination table names, which is finer than the destination it resolves to.
public enum AppKind: String, Sendable, Equatable, CaseIterable, Codable {
    case chat
    case email
    case codeEditor
    case terminal
    case sqlEditor
    case spreadsheet
    case notes
    case documentEditor

    /// Where words typed into this sort of app are going; a terminal and an editor want the same treatment.
    public var destination: Destination {
        switch self {
        case .chat: .messaging
        case .email: .email
        case .codeEditor, .terminal: .codeEditor
        case .sqlEditor: .sqlEditor
        case .spreadsheet: .spreadsheet
        case .notes, .documentEditor: .document
        }
    }

    /// The kind a destination reads as on its own, or nil for plain text, which names no sort of place.
    public init?(_ destination: Destination) {
        switch destination {
        case .messaging: self = .chat
        case .email: self = .email
        case .codeEditor: self = .codeEditor
        case .sqlEditor: self = .sqlEditor
        case .spreadsheet: self = .spreadsheet
        case .document: self = .documentEditor
        case .plain: return nil
        }
    }

    /// The kind the one table gives this app, or nil for an app no row names.
    public init?(
        applicationName: String? = nil, bundleIdentifier: String? = nil,
        rules: [DestinationRule] = DestinationRules.standard
    ) {
        let app = AppContext(applicationName: applicationName, bundleIdentifier: bundleIdentifier)
        guard let kind = DestinationClassifier.kind(for: app, rules: rules) else { return nil }
        self = kind
    }

    /// The kind that names a situation, which is always one the destination in force resolves to.
    public init?(naming situation: Situation, rules: [DestinationRule] = DestinationRules.standard) {
        if let kind = DestinationClassifier.kind(for: situation.app, rules: rules),
            kind.destination == situation.destination
        {
            self = kind
            return
        }
        self.init(situation.destination)
    }
}
