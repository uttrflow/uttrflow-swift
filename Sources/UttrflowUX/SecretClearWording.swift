// What a "Copied" notice adds for a secret, so the person knows the clipboard will not keep it.

/// When a copied secret leaves the clipboard, in the one wording every notice uses. See `Docs/insertion.md`.
enum SecretClearWording {
    /// "It leaves the clipboard in 60 seconds", or `nil` when clearing is off.
    static func sentence(afterSeconds seconds: Int) -> String? {
        guard seconds > 0 else { return nil }
        return "It leaves the clipboard in \(seconds) \(seconds == 1 ? "second" : "seconds")"
    }
}
