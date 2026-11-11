// What a "Copied" notice adds for a secret, so the person knows the clipboard will not keep it.

/// When a copied secret leaves the clipboard, in the one wording every notice uses. See `Docs/insertion.md`.
public enum SecretClearWording {
    /// "It leaves the clipboard in 60 seconds", or `nil` when clearing is off.
    public static func sentence(afterSeconds seconds: Int) -> String? {
        guard seconds > 0 else { return nil }
        return "It leaves the clipboard in \(seconds) \(seconds == 1 ? "second" : "seconds")"
    }
}

extension PanelNotice {
    /// The same notice with the clearing sentence after it; unchanged when clearing is off.
    public func namingSecretClear(afterSeconds seconds: Int) -> PanelNotice {
        guard let sentence = SecretClearWording.sentence(afterSeconds: seconds) else { return self }
        let joined = message.hasSuffix(".") ? "\(message) \(sentence)." : "\(message). \(sentence)"
        return PanelNotice(
            symbolName: symbolName, message: joined, action: action, announcementID: announcementID)
    }
}
