/// Finds what a set of strings agree on, which is the only text that can be inserted blind.
enum CommonPrefix {
    /// The longest opening every string shares by Unicode scalar, empty when they agree on nothing.
    static func of(_ texts: [String]) -> String {
        guard let first = texts.first else { return "" }
        guard texts.count > 1 else { return first }
        var shared = Array(first.unicodeScalars)
        for text in texts.dropFirst() {
            shared = Array(zip(shared, text.unicodeScalars).prefix { $0.0 == $0.1 }.map(\.0))
            if shared.isEmpty { break }
        }
        return String(String.UnicodeScalarView(shared))
    }
}
