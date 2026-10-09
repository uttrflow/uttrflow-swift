/// The line a completion continues, which the field read and the suggestion gate both measure.
public enum TypedLine {
    /// Beyond this many characters a field is a document, and its whole value is not a prefix worth matching.
    public static let maximumLength = 256
}
