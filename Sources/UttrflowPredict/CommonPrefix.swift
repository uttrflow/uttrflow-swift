/// Finds what a set of strings agree on, which is the only text that can be inserted blind.
public enum CommonPrefix {
    /// The longest opening every string shares, empty when they agree on nothing.
    public static func of(_ texts: [String]) -> String {
        guard let first = texts.first else { return "" }
        guard texts.count > 1 else { return first }
        var shared = first
        for text in texts.dropFirst() {
            shared = String(zip(shared, text).prefix { $0.0 == $0.1 }.map(\.0))
            if shared.isEmpty { break }
        }
        return shared
    }
}
