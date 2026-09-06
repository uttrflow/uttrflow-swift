// What a shortcut is for, so a binding can say which one it belongs to. See `Docs/shortcuts.md`.

/// Something the user can reach from any app by pressing keys.
public enum ShortcutAction: String, Sendable, Equatable, CaseIterable, Codable {
    /// Hold to speak, release to insert.
    case dictate
    /// Open the clipboard panel.
    case clipboard
}
