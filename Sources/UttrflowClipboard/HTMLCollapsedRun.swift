/// A text run with its inner whitespace collapsed to one space and its edge whitespace remembered.
struct CollapsedRun {
    let body: String
    let hasLeadingSpace: Bool
    let hasTrailingSpace: Bool

    init(_ text: String) {
        var out = String.UnicodeScalarView()
        var leading = false
        var pending = false
        for scalar in text.unicodeScalars {
            guard !scalar.properties.isWhitespace else {
                pending = true
                continue
            }
            if pending {
                if out.isEmpty { leading = true } else { out.append(" ") }
                pending = false
            }
            out.append(scalar)
        }
        body = String(out)
        hasLeadingSpace = leading
        // A run of only whitespace still separates its neighbours.
        hasTrailingSpace = pending
    }
}
