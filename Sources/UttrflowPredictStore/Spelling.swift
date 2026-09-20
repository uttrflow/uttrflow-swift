// The one encoding a line is stored and matched under.
private import Foundation

/// Folds the encodings Unicode allows for one accented letter into one, because SQLite compares bytes.
enum Spelling {
    /// The text in its precomposed form, so an accent typed as one scalar or two is the same line.
    static func canonical(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping
    }

    /// Whether the text is already stored as its canonical bytes, which `==` cannot tell since it ignores encoding.
    static func isCanonical(_ text: String) -> Bool {
        text.utf8.elementsEqual(canonical(text).utf8)
    }
}
