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

    /// Exact labels that name each role. Labels are supplied by the field and may contain arbitrary page text.
    static let labelWords: [(role: FieldRole, phrases: Set<String>)] = [
        (.recipient, ["to", "cc", "bcc", "recipient", "recipients"]),
        (.subject, ["subject"]),
        (.addressBar, ["url"]),
        (.search, ["search", "search mail"]),
    ]

    /// The role a field's structure declares first, then an exact known label when its structure is unknown.
    public init(accessibilityRole: String?, isMultiline: Bool?, label: String?, subrole: String? = nil) {
        if accessibilityRole == SecureField.secureRole || subrole == SecureField.secureRole {
            self = .unknown
        } else if accessibilityRole == "AXSearchField" {
            self = .search
            return
        } else if isMultiline == true || accessibilityRole == "AXTextArea" {
            self = .message
        } else if isMultiline == false || accessibilityRole == "AXTextField" {
            self = .singleLine
        } else {
            let phrase = (label ?? "").lowercased()
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: " ")
            if let named = Self.labelWords.first(where: { $0.phrases.contains(phrase) }) {
                self = named.role
            } else {
                self = .unknown
            }
        }
    }
}
