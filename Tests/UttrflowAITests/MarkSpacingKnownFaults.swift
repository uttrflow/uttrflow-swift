/// Matrix cells and dash pairs that fail today, each with the issue that fixes it; the lists only shrink.
enum MarkSpacingKnownFaults {
    /// Cells by notation row and position, failing in at least one destination.
    static let cells: [String: Int] = [:]

    /// Pairs of dash sources, first then second, that write two styles in at least one destination.
    static let dashes: [String: Int] = [:]
}
