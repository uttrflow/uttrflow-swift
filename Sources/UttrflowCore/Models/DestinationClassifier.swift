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

    public init(
        bundlePrefixes: [String] = [], titleContains: [String] = [], nameWords: [String] = [],
        destination: Destination
    ) {
        self.bundlePrefixes = bundlePrefixes
        self.titleContains = titleContains
        self.nameWords = nameWords
        self.kind = nil
        self.destination = destination
    }

    /// A row built from the sort of app it names, so its destination cannot disagree with its caption.
    public init(
        bundlePrefixes: [String] = [], titleContains: [String] = [], nameWords: [String] = [],
        kind: AppKind
    ) {
        self.bundlePrefixes = bundlePrefixes
        self.titleContains = titleContains
        self.nameWords = nameWords
        self.kind = kind
        self.destination = kind.destination
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

    /// Whether the app's window title falls under this row, which decides only an app no row names.
    public func matchesTitle(_ app: AppContext) -> Bool {
        guard let title = app.documentName?.lowercased(), !title.isEmpty else { return false }
        return titleContains.contains { DestinationRule.title(title, names: $0.lowercased()) }
    }

    /// Whether the fragment stands as whole words in the title, so "Gmail" is not read out of "gmailer".
    static func title(_ title: String, names fragment: String) -> Bool {
        guard !fragment.isEmpty, title.count >= fragment.count else { return false }
        let title = Array(title)
        let fragment = Array(fragment)
        for start in 0...(title.count - fragment.count)
        where Array(title[start..<(start + fragment.count)]) == fragment {
            let end = start + fragment.count
            let opens = start == 0 || !isWordCharacter(title[start - 1])
            let closes = end == title.count || !isWordCharacter(title[end])
            if opens && closes { return true }
        }
        return false
    }

    /// A letter or a digit, which is what the rule above counts as part of a word.
    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
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

    /// Every row's bundle identifiers, then their titles, then their names; a title never beats an identifier.
    public static func rule(
        for app: AppContext, rules: [DestinationRule] = DestinationRules.standard
    ) -> DestinationRule? {
        rules.first { $0.matchesBundle(app) }
            ?? rules.first { $0.matchesTitle(app) }
            ?? rules.first { $0.matchesName(app) }
    }

    /// The sort of app the table calls this one, which is what the prompt's caption is written from.
    public static func kind(
        for app: AppContext, rules: [DestinationRule] = DestinationRules.standard
    ) -> AppKind? {
        rule(for: app, rules: rules)?.kind
    }
}
