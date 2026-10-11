internal import UttrflowCore

/// What a name stands for in code, which decides the style a file writes it in.
enum NameRole: Sendable, Equatable, CaseIterable {
    /// A variable, property, parameter or function.
    case value
    /// A class, struct, enum, protocol or trait.
    case type
    /// A constant written in the language's constant style.
    case constant
}

/// The style a file writes each kind of name in, read from the identifiers on screen and the language's own default.
struct NamingConvention: Sendable, Equatable {
    private let styles: [NameRole: NameStyle]

    /// The fewest identifiers in one style that overturn the language's default.
    static let overturningCount = 2

    /// The convention the screen shows for each role, else the language's, else none.
    static func infer(from vocabulary: ScreenVocabulary, language: CodeLanguage?) -> NamingConvention {
        let shown = vocabulary.identifiers.compactMap { NameStyle(identifier: $0) }
        let defaults = language.map(defaultStyles) ?? [:]
        var styles = defaults
        if let value = leading(shown, among: [.camel, .snake], default: defaults[.value]) {
            styles[.value] = value
        }
        if shown.contains(.pascal), styles[.type] == nil { styles[.type] = .pascal }
        if let constant = leading(shown, among: [.screamingSnake], default: defaults[.constant]) {
            styles[.constant] = constant
        }
        return NamingConvention(styles: styles)
    }

    /// The style a role is written in, or `nil` when neither the screen nor the language says.
    func style(for role: NameRole) -> NameStyle? { styles[role] }

    /// The words as one name: in the style the speaker asked for, else the file's for this role, else `nil` and the words stay as spoken.
    func name(_ words: [String], role: NameRole, explicit: NameStyle? = nil) -> String? {
        guard !words.isEmpty, words.allSatisfy(Self.isPlainWord), let style = explicit ?? styles[role] else {
            return nil
        }
        return style.write(words)
    }

    private static func isPlainWord(_ word: String) -> Bool {
        !word.isEmpty && word.allSatisfy { $0.isLetter || $0.isNumber }
    }

    /// The style most often shown among `candidates`, when it clears a tie and, against a default, the overturning count.
    private static func leading(
        _ shown: [NameStyle], among candidates: [NameStyle], default fallback: NameStyle?
    ) -> NameStyle? {
        let counts = candidates.map { style in (style, shown.count { $0 == style }) }
        guard let best = counts.max(by: { $0.1 < $1.1 }), best.1 > 0,
            counts.filter({ $0.1 == best.1 }).count == 1
        else { return nil }
        guard let fallback, fallback != best.0 else { return best.0 }
        return best.1 >= overturningCount ? best.0 : nil
    }

    /// What each language writes by default; a language outside this table has no default.
    private static func defaultStyles(_ language: CodeLanguage) -> [NameRole: NameStyle] {
        switch language {
        case .swift: [.value: .camel, .type: .pascal, .constant: .camel]
        case .javascript, .typescript, .java: [.value: .camel, .type: .pascal, .constant: .screamingSnake]
        case .python, .rust, .ruby: [.value: .snake, .type: .pascal, .constant: .screamingSnake]
        case .go: [.value: .camel, .type: .pascal, .constant: .camel]
        case .json, .sql, .shell, .html, .css: [:]
        }
    }
}
