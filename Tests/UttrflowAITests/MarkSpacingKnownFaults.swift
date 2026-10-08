/// Matrix cells and dash pairs that fail today, each with the issue that fixes it; the lists only shrink.
enum MarkSpacingKnownFaults {
    /// Cells by notation row and position, failing in at least one destination.
    static let cells: [String: Int] = [
        "mark.at-sign beforeBracket": 6607,
        "mark.at-sign beforeQuote": 6607,
        "mark.hash-sign beforeBracket": 6607,
        "mark.hash-sign beforeQuote": 6607,
        "mark.open-quote beforeBracket": 6607,
        "mark.open-quote beforeQuote": 6607,
        "mark.open-single-quote beforeBracket": 6607,
        "mark.open-single-quote beforeQuote": 6607,
        "mark.quote beforeQuote": 6607,
    ]

    /// Pairs of dash sources, first then second, that write two styles in at least one destination.
    static let dashes: [String: Int] = [:]
}
