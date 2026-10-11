/// Whether a suggestion can be shown and inserted without hidden or terminal-active scalars.
public enum SuggestionTextSafety {
    /// Rejects control and format scalars and the replacement character, except the joiners and tags inside an emoji sequence.
    public static func allows(_ text: some StringProtocol) -> Bool {
        let scalars = Array(text.unicodeScalars)
        return scalars.indices.allSatisfy { index in
            let scalar = scalars[index]
            let category = scalar.properties.generalCategory
            guard category == .control || category == .format || scalar.value == 0xFFFD else { return true }
            if scalar.value == 0x200D { return joinsEmoji(scalars, at: index) }
            if isTag(scalar) { return endsTagSequence(scalars, at: index) }
            return false
        }
    }

    /// Whether the joiner at `index` sits between two emoji scalars.
    private static func joinsEmoji(_ scalars: [Unicode.Scalar], at index: Int) -> Bool {
        guard index > 0, index + 1 < scalars.count else { return false }
        return isPictograph(scalars[index - 1]) || scalars[index - 1].value == 0xFE0F
            ? isPictograph(scalars[index + 1]) : false
    }

    /// Whether the tag at `index` belongs to a run that follows an emoji base and closes with the cancel tag.
    private static func endsTagSequence(_ scalars: [Unicode.Scalar], at index: Int) -> Bool {
        var start = index
        while start > 0, isTag(scalars[start - 1]) { start -= 1 }
        guard start > 0, isPictograph(scalars[start - 1]) else { return false }
        var end = index
        while end + 1 < scalars.count, isTag(scalars[end]) { end += 1 }
        return isTag(scalars[end]) && scalars[end].value == 0xE007F
    }

    private static func isTag(_ scalar: Unicode.Scalar) -> Bool { (0xE0020...0xE007F).contains(scalar.value) }

    private static func isPictograph(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isEmoji && scalar.value > 0xFF
    }
}
