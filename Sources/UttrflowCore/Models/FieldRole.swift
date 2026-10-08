// What a focused field is for, so a subject, a recipient list and a search box are formatted apart.

/// The purpose of the focused field, decided from its Accessibility role, its line count and its label.
public enum FieldRole: String, Sendable, Equatable, CaseIterable, Codable {
    /// A box whose text is a query, typed as spoken.
    case search
    /// A browser's address and search bar.
    case addressBar
    /// A list of addresses: To, Cc, Bcc.
    case recipient
    /// A message's subject line.
    case subject
    /// A body that holds paragraphs.
    case message
    /// Any other one-line field.
    case singleLine
    /// Nothing the field says decides it.
    case unknown

    /// Label words that name each role, matched as whole lower-cased words. See `Docs/context-accessibility.md`.
    static let labelWords: [(role: FieldRole, words: Set<String>)] = [
        (.recipient, ["to", "cc", "bcc", "recipient", "recipients"]),
        (.subject, ["subject"]),
        (.addressBar, ["url"]),
        (.search, ["search"]),
    ]

    /// The role a field's names declare: an explicit search role first, then the label, then the line count.
    public init(accessibilityRole: String?, isMultiline: Bool?, label: String?) {
        if accessibilityRole == "AXSearchField" {
            self = .search
            return
        }
        let words = Set(
            (label ?? "").lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
        if let named = Self.labelWords.first(where: { !$0.words.isDisjoint(with: words) }) {
            self = named.role
        } else if isMultiline == true || accessibilityRole == "AXTextArea" {
            self = .message
        } else if isMultiline == false || accessibilityRole == "AXTextField" {
            self = .singleLine
        } else {
            self = .unknown
        }
    }
}
