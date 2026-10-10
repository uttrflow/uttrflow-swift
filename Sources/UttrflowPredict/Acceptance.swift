/// What accepting a suggestion does to the field. See `Docs/predict-accept.md`.
public enum Acceptance {
    /// The characters to take back from before the caret, and the text to put in their place.
    public struct Edit: Sendable, Equatable {
        /// The already-typed characters this destroys, empty when the suggestion only adds.
        public let replaced: String
        /// The text that goes in at the caret.
        public let inserted: String

        public init(replaced: String, inserted: String) {
            self.replaced = replaced
            self.inserted = inserted
        }

        /// How many characters before the caret go, which is what a backspace route counts.
        public var replacedCount: Int { replaced.count }

        /// Whether this destroys text the user typed rather than only adding to it.
        public var isReplacement: Bool { !replaced.isEmpty }

        /// The line this leaves behind, which is what the surface draws ahead of the keypress.
        public func applied(to typed: String) -> String {
            String(typed.dropLast(replacedCount)) + inserted
        }
    }

    /// The edit that turns what is typed into the suggestion, or `nil` when it already is it.
    public static func edit(accepting suggestion: String, after typed: String) -> Edit? {
        let shared = CommonPrefix.of([typed, suggestion]).unicodeScalars.count
        let replaceFrom = lastCharacterBoundary(in: typed, noLaterThan: shared)
        let edit = Edit(
            replaced: String(String.UnicodeScalarView(typed.unicodeScalars.dropFirst(replaceFrom))),
            inserted: String(String.UnicodeScalarView(suggestion.unicodeScalars.dropFirst(replaceFrom))))
        return edit.replaced.isEmpty && edit.inserted.isEmpty ? nil : edit
    }

    /// Backs a scalar prefix up to a boundary the target can delete as one character.
    private static func lastCharacterBoundary(in text: String, noLaterThan scalarCount: Int) -> Int {
        var boundary = 0
        for character in text {
            let next = boundary + String(character).unicodeScalars.count
            guard next <= scalarCount else { break }
            boundary = next
        }
        return boundary
    }

    /// The edit re-aimed at what the field holds before the caret now, or `nil` when the field no longer fits it.
    public static func rebase(_ edit: Edit, after typed: String, onto before: String) -> Edit? {
        guard !edit.isReplacement else { return before.hasSuffix(typed) ? edit : nil }
        return rebaseAhead(edit, after: typed, onto: before) ?? (before.hasSuffix(typed) ? edit : nil)
    }

    /// Finds the longest start of the inserted text the field already holds past `typed`, and inserts only the rest.
    private static func rebaseAhead(_ edit: Edit, after typed: String, onto before: String) -> Edit? {
        let inserted = Array(edit.inserted)
        guard !inserted.isEmpty else { return nil }
        for echoed in stride(from: inserted.count, through: 1, by: -1) {
            let ahead = typed + String(inserted[..<echoed])
            if before.hasSuffix(ahead) {
                return Edit(replaced: "", inserted: String(inserted[echoed...]))
            }
        }
        return nil
    }
}
