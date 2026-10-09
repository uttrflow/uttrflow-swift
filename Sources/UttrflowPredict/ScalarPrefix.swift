import Foundation

extension StringProtocol {
    /// Whether `self` opens with `prefix`, comparing canonically decomposed Unicode scalars so a base letter typed ahead of its own combining mark still matches, whichever form either side is stored in.
    func hasScalarPrefix<Prefix: StringProtocol>(_ prefix: Prefix) -> Bool {
        var mine = String(self).decomposedStringWithCanonicalMapping.unicodeScalars.makeIterator()
        var theirs = String(prefix).decomposedStringWithCanonicalMapping.unicodeScalars.makeIterator()
        while let wanted = theirs.next() {
            guard let has = mine.next(), has == wanted else { return false }
        }
        return true
    }
}
