public import UttrflowCore

// Every shortcut the user can change, in one list. See `Docs/shortcuts.md`.

/// One bindable shortcut: what it is called, and what it does.
public struct ShortcutDescriptor: Sendable, Equatable {
    /// Which shortcut this describes.
    public let action: ShortcutAction
    /// The row's label, in the user's words rather than the code's.
    public let label: String
    /// One sentence under the label, or nothing when the label says it all.
    public let explanation: String?
}

/// The list the shortcuts screen is drawn from; adding a shortcut is adding an entry here.
public enum ShortcutRegistry {
    /// Every shortcut, in the order the screen shows them.
    public static let all: [ShortcutDescriptor] = [
        ShortcutDescriptor(
            action: .dictate,
            label: "Dictate",
            explanation: "Hold to talk, and release to insert what you said."),
        ShortcutDescriptor(
            action: .clipboard,
            label: "Clipboard",
            explanation: "Opens the clipboard panel from any app."),
    ]

    /// The entry for one action; every action has one, so this cannot fail.
    public static func descriptor(for action: ShortcutAction) -> ShortcutDescriptor {
        all.first { $0.action == action } ?? all[0]
    }

    /// What one action is called, for a sentence that has to name it.
    public static func label(for action: ShortcutAction) -> String {
        descriptor(for: action).label
    }
}
