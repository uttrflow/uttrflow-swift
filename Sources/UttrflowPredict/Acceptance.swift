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
    }

    /// The edit that turns what is typed into the suggestion, or `nil` when it already is it.
    public static func edit(accepting suggestion: String, after typed: String) -> Edit? {
        let shared = CommonPrefix.of([typed, suggestion]).count
        let edit = Edit(
            replaced: String(typed.dropFirst(shared)),
            inserted: String(suggestion.dropFirst(shared)))
        return edit.replaced.isEmpty && edit.inserted.isEmpty ? nil : edit
    }
}
