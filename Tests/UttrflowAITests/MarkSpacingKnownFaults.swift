/// Matrix cells and dash pairs that fail today, each with the issue that fixes it; the lists only shrink.
enum MarkSpacingKnownFaults {
    /// Cells by notation row and position, failing in at least one destination.
    static let cells: [String: Int] = [
        "mark.semi-colon start": 6608
    ]

    /// Pairs of dash sources, first then second, that write two styles in at least one destination.
    static let dashes: [String: Int] = [
        "glued spaced": 6609,
        "glued spoken": 6609,
        "spaced glued": 6609,
        "spoken glued": 6609,
    ]
}
