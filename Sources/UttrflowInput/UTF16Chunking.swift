// Where a string may be cut for an API that counts UTF-16 units, which is a rule rather than a call.
/// Splits text into pieces a synthetic keystroke can carry without cutting a character in half.
public enum UTF16Chunking {
    /// Pieces of at most `limit` UTF-16 units, never splitting a scalar, so an emoji is never a lone surrogate.
    public static func chunks(of text: String, limit: Int) -> [[UInt16]] {
        guard limit > 0 else { return [] }

        var chunks: [[UInt16]] = []
        var current: [UInt16] = []
        for scalar in text.unicodeScalars {
            let units = Array(String(scalar).utf16)
            // No scalar is wider than two units, so a scalar always fits a limit of two or more.
            if current.count + units.count > limit, !current.isEmpty {
                chunks.append(current)
                current = []
            }
            current += units
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }
}
