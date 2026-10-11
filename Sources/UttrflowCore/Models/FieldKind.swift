// The kinds of field a destination's formatter tells apart.

/// Which field of a destination the words go into, as `DestinationFormatter.fieldKind(of:)` decides it.
public enum FieldKind: String, Sendable, Equatable, CaseIterable, Codable {
    /// The app's own body or editor, where the destination's formatter applies unchanged.
    case primary
    /// A field that holds one line.
    case oneLine = "one-line"
    /// A search box, or every field of a launcher panel, whose text is a query.
    case search
    /// An email's list of addresses.
    case recipient
    /// An email's subject line.
    case subject
}
