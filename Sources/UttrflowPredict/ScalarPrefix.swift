extension StringProtocol {
    /// Whether `self` opens with `prefix`, comparing Unicode scalars so a base letter typed ahead of its own combining mark still matches.
    func hasScalarPrefix<Prefix: StringProtocol>(_ prefix: Prefix) -> Bool {
        var mine = unicodeScalars.makeIterator()
        var theirs = prefix.unicodeScalars.makeIterator()
        while let wanted = theirs.next() {
            guard let has = mine.next(), has == wanted else { return false }
        }
        return true
    }
}
