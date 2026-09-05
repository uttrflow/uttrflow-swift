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
        let bundle = app.bundleIdentifier?.lowercased() ?? ""
        let title = app.documentName?.lowercased() ?? ""
        return bundlePrefixes.contains { !bundle.isEmpty && bundle.hasPrefix($0.lowercased()) }
            || titleContains.contains { !title.isEmpty && title.contains($0.lowercased()) }
    }
}

/// Decides where the words are going by reading one table, so adding an app is a row.
public enum DestinationClassifier {
    /// The first rule that matches wins; an app no rule names is `.plain`.
    public static func classify(
        _ app: AppContext, rules: [DestinationRule] = DestinationRules.standard
    ) -> Destination {
        rules.first { $0.matches(app) }?.destination ?? .plain
    }
}
