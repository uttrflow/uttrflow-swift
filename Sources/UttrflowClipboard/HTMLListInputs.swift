/// Reads the list metadata in an HTML token stream.
enum HTMLListInputs {
    /// How many items each list holds directly, in the order the lists open, nesting as `apply` does.
    static func itemCounts(in tokens: [HTMLToken]) -> [Int] {
        var counts: [Int] = []
        var open: [Int] = []
        for case .tag(let tag) in tokens {
            switch tag.name {
            case "ul", "ol", "menu":
                if tag.isClosing {
                    if !open.isEmpty { open.removeLast() }
                } else {
                    open.append(counts.count)
                    counts.append(0)
                }
            case "li" where !tag.isClosing:
                if let list = open.last { counts[list] += 1 }
            default:
                break
            }
        }
        return counts
    }

    /// An attribute's integer the way HTML reads one: leading space, a sign, then digits, and the rest ignored.
    static func integer(_ text: String?) -> Int? {
        guard let text else { return nil }
        var rest = Substring(text.drop(while: \.isWhitespace))
        let isNegative = rest.first == "-"
        if rest.first == "-" || rest.first == "+" { rest = rest.dropFirst() }
        let digits = rest.prefix(while: \.isASCII).prefix(while: \.isNumber)
        guard !digits.isEmpty, let magnitude = Int(digits) else { return nil }
        return isNegative ? -magnitude : magnitude
    }
}
