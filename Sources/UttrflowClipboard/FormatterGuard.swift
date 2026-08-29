/// Decides whether a formatter's output may be shown to the user at all.
///
/// The specification is unusually direct about this, and it is right:
///
/// > A model that silently drops a line, changes a string literal, or normalises a number
/// > has corrupted something the user will paste into production and may not read first.
/// > If a formatter's output does not round-trip to the same tokens, discard it and paste
/// > the original. That rule is D6 and D7, and it is what makes this feature safe to ship.
///
/// So this is the gate, and it is deliberately the only thing standing between a
/// formatter and the clipboard. Everything else about formatting is a convenience;
/// this is the part that makes the convenience affordable.
///
/// It compares what the code *says* rather than how it is written: the words, the numbers
/// and the contents of the strings, in order. That lets a formatter do the things
/// formatters legitimately do — reindent, rewrap, add a trailing comma, change `'a'` to
/// `"a"`, put a brace on its own line — while catching the three failures named above,
/// each of which changes the sequence.
public enum FormatterGuard {
    /// Whether `formatted` may be offered in place of `original`.
    ///
    /// Conservative by construction: anything this cannot account for reads as a
    /// difference and is refused. A refused formatting costs the user a convenience; an
    /// accepted corruption costs them something they may not notice until it is running.
    public static func isFaithful(_ formatted: String, to original: String) -> Bool {
        significant(formatted) == significant(original)
    }

    /// The words, numbers and string contents of some code, in order.
    ///
    /// Punctuation is dropped, which is what gives a formatter room to work: braces,
    /// commas, semicolons and quote characters are how code is *written*, not what it
    /// says. Whitespace is dropped for the same reason, and dropping it is also what makes
    /// a rewrapped comment invisible here while a deleted one is not — its words simply
    /// stop being in the list.
    static func significant(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""

        for character in text {
            if character.isLetter || character.isNumber || character == "_" {
                current.append(character)
            } else if !current.isEmpty {
                tokens.append(current)
                current = ""
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }
}
