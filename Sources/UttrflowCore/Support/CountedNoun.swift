// The English noun a count takes, and the two together.

/// The noun a count uses: singular at exactly one, plural otherwise; English-only, like the rest of the voice.
public enum CountedNoun {
    /// The noun alone: "character" at one, "characters" otherwise.
    public static func of(_ count: Int, _ singular: String, _ plural: String) -> String {
        count == 1 ? singular : plural
    }

    /// The count and its noun: "1 character", "0 characters".
    public static func count(_ count: Int, _ singular: String, _ plural: String) -> String {
        "\(count) \(of(count, singular, plural))"
    }
}
