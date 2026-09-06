/// One row of the table that turns an app into a destination.
public struct DestinationRule: Sendable, Equatable, Codable {
    /// Bundle identifiers this row covers, matched as case-insensitive prefixes.
    public let bundlePrefixes: [String]
    /// Window-title fragments this row covers, for apps that live in a browser tab.
    public let titleContains: [String]
    public let destination: Destination

    public init(bundlePrefixes: [String] = [], titleContains: [String] = [], destination: Destination) {
        self.bundlePrefixes = bundlePrefixes
        self.titleContains = titleContains
        self.destination = destination
    }

    /// Whether the app's bundle identifier or window title falls under this row.
    public func matches(_ app: AppContext) -> Bool {
        matchesBundle(app) || matchesTitle(app)
    }

    /// Whether the app's bundle identifier falls under this row.
    public func matchesBundle(_ app: AppContext) -> Bool {
        guard let bundle = app.bundleIdentifier?.lowercased(), !bundle.isEmpty else { return false }
        return bundlePrefixes.contains { bundle.hasPrefix($0.lowercased()) }
    }

    /// Whether the app's window title falls under this row, which decides only an app no row names.
    public func matchesTitle(_ app: AppContext) -> Bool {
        guard let title = app.documentName?.lowercased(), !title.isEmpty else { return false }
        return titleContains.contains { title.contains($0.lowercased()) }
    }
}

/// Decides where the words are going by reading one table, so adding an app is a row.
public enum DestinationClassifier {
    /// The user's answer, then every row's bundle identifiers, then their titles; a title never beats an identifier.
    public static func classify(
        _ app: AppContext, rules: [DestinationRule] = DestinationRules.standard,
        overrides: DestinationOverrides = .none
    ) -> Destination {
        overrides.destination(for: app)
            ?? rules.first { $0.matchesBundle(app) }?.destination
            ?? rules.first { $0.matchesTitle(app) }?.destination
            ?? .plain
    }
}
