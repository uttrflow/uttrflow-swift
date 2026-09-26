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
        let shared = CommonPrefix.of([typed, suggestion]).count
        let edit = Edit(
            replaced: String(typed.dropFirst(shared)),
            inserted: String(suggestion.dropFirst(shared)))
        return edit.replaced.isEmpty && edit.inserted.isEmpty ? nil : edit
    }

    /// The edit re-aimed at what the field holds before the caret now, or `nil` when the field no longer fits it.
    public static func rebase(_ edit: Edit, after typed: String, onto before: String) -> Edit? {
        guard before.hasSuffix(typed) else {
            // Characters typed since the read can only be matched against an insert, so a replacement must see the line it read.
            return edit.isReplacement ? nil : rebaseAhead(edit, after: typed, onto: before)
        }
        return edit
    }

    /// Finds the longest start of the inserted text the field already holds past `typed`, and inserts only the rest.
    private static func rebaseAhead(_ edit: Edit, after typed: String, onto before: String) -> Edit? {
        let inserted = Array(edit.inserted)
        for echoed in stride(from: inserted.count - 1, through: 1, by: -1) {
            let ahead = typed + String(inserted[..<echoed])
            if before.hasSuffix(ahead) {
                return Edit(replaced: "", inserted: String(inserted[echoed...]))
            }
        }
        return nil
    }
}
