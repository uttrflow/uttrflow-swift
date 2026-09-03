/// What accepting a suggestion actually puts into the field.
public enum Acceptance {
    /// The tail to insert, or `nil` when the suggestion adds nothing. See `Docs/predict-accept.md`.
    public static func remainder(of suggestion: String, after typed: String) -> String? {
        guard suggestion.hasPrefix(typed) else { return nil }
        let rest = String(suggestion.dropFirst(typed.count))
        return rest.isEmpty ? nil : rest
    }
}
