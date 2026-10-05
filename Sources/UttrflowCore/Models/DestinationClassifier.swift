import Foundation

/// One row of the table that turns an app into a destination.
public struct DestinationRule: Sendable, Equatable, Codable {
    /// Bundle identifiers this row covers, matched as case-insensitive prefixes.
    public let bundlePrefixes: [String]
    /// Window-title fragments this row covers, for apps that live in a browser tab.
    public let titleContains: [String]
    /// Whole words of the application name this row covers, for an app macOS names but will not identify.
    public let nameWords: [String]
    /// The sort of app this row names, or nil for a row built from a destination alone.
    public let kind: AppKind?
    public let destination: Destination
    /// A stop policy this app needs in addition to its destination's other formatting rules.
    public let terminalStop: TerminalStopPolicy?
    /// What every field of this app holds, for a panel whose one input is a query whatever role it reports.
    public let field: FieldRole?

    public init(
        bundlePrefixes: [String] = [], titleContains: [String] = [], nameWords: [String] = [],
        destination: Destination, terminalStop: TerminalStopPolicy? = nil, field: FieldRole? = nil
    ) {
        self.bundlePrefixes = bundlePrefixes
        self.titleContains = titleContains
        self.nameWords = nameWords
        self.kind = nil
        self.destination = destination
        self.terminalStop = terminalStop
        self.field = field
    }

    /// A row built from the sort of app it names, so its destination cannot disagree with its caption.
    public init(
        bundlePrefixes: [String] = [], titleContains: [String] = [], nameWords: [String] = [],
        kind: AppKind, terminalStop: TerminalStopPolicy? = nil, field: FieldRole? = nil
    ) {
        self.bundlePrefixes = bundlePrefixes
        self.titleContains = titleContains
        self.nameWords = nameWords
        self.kind = kind
        self.destination = kind.destination
        self.terminalStop = terminalStop
        self.field = field
    }

    /// Whether the app's bundle identifier, window title or name falls under this row.
    public func matches(_ app: AppContext) -> Bool {
        matchesBundle(app) || matchesTitle(app) || matchesName(app)
    }

    /// Whether the app's bundle identifier falls under this row.
    public func matchesBundle(_ app: AppContext) -> Bool {
        guard let bundle = app.bundleIdentifier?.lowercased(), !bundle.isEmpty else { return false }
        return bundlePrefixes.contains { bundle.hasPrefix($0.lowercased()) }
    }

    /// Whether the app's window title names this row's app at its edge, which decides only an app no row names.
    public func matchesTitle(_ app: AppContext) -> Bool {
        guard let title = app.documentName?.lowercased(), !title.isEmpty else { return false }
        return titleContains.contains { DestinationRule.title(title, names: $0.lowercased()) }
    }

    /// Whether the fragment is the title's first or last segment, the place a hosted web app writes its own name.
    static func title(_ title: String, names fragment: String) -> Bool {
        guard !fragment.isEmpty else { return false }
        let segments = titleSegments(title)
        guard let first = segments.first, let last = segments.last else { return false }
        return first == fragment || last == fragment
    }

    /// The separators a browser tab puts between a page's subject and the app that hosts it.
    private static let titleSeparators = [" - ", " | ", " – ", " — ", " · ", " • "]

    /// The title split at its separators, trimmed, with a leading unread count such as "(3) " removed.
    static func titleSegments(_ title: String) -> [String] {
        var segments = [title]
        for separator in titleSeparators {
            segments = segments.flatMap { $0.components(separatedBy: separator) }
        }
        return segments.map { withoutUnreadCount($0.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.isEmpty }
    }

    /// The segment without a leading parenthesised number, which a web app adds for unread items.
    private static func withoutUnreadCount(_ segment: String) -> String {
        guard segment.hasPrefix("("), let close = segment.firstIndex(of: ")") else { return segment }
        let inside = segment[segment.index(after: segment.startIndex)..<close]
        guard !inside.isEmpty, inside.allSatisfy({ $0.isNumber || $0 == "+" }) else { return segment }
        return segment[segment.index(after: close)...].trimmingCharacters(in: .whitespaces)
    }

    /// Whether a whole word of the app's name falls under this row, so "Barcode Buddy" is not an editor.
    public func matchesName(_ app: AppContext) -> Bool {
        guard let name = app.applicationName, !name.isEmpty, !nameWords.isEmpty else { return false }
        let words = Set(WordShape.words(name))
        return nameWords.contains { words.contains($0.lowercased()) }
    }
}

/// Decides where the words are going by reading one table, so adding an app is a row.
public enum DestinationClassifier {
    /// The user's answer, then the table's, then plain text.
    public static func classify(
        _ app: AppContext, rules: [DestinationRule] = DestinationRules.standard,
        overrides: DestinationOverrides = .none
    ) -> Destination {
        overrides.destination(for: app) ?? rule(for: app, rules: rules)?.destination ?? .plain
    }

    /// The most specific bundle prefix, then the first matching title, then the first matching name.
    public static func rule(
        for app: AppContext, rules: [DestinationRule] = DestinationRules.standard
    ) -> DestinationRule? {
        if let bundle = app.bundleIdentifier?.lowercased(), !bundle.isEmpty {
            var bestBundleRule: DestinationRule?
            var bestPrefixLength = 0
            for rule in rules {
                for prefix in rule.bundlePrefixes {
                    let prefix = prefix.lowercased()
                    guard !prefix.isEmpty, bundle.hasPrefix(prefix) else { continue }
                    // Strictly greater keeps the earlier row as the stable tie-break for equal prefixes.
                    if prefix.count > bestPrefixLength {
                        bestBundleRule = rule
                        bestPrefixLength = prefix.count
                    }
                }
            }
            if let bestBundleRule { return bestBundleRule }
        }
        return rules.first { $0.matchesTitle(app) } ?? rules.first { $0.matchesName(app) }
    }

    /// The sort of app the table calls this one, which is what the prompt's caption is written from.
    public static func kind(
        for app: AppContext, rules: [DestinationRule] = DestinationRules.standard
    ) -> AppKind? {
        rule(for: app, rules: rules)?.kind
    }
}
