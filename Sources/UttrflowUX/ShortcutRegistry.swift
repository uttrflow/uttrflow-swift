public import UttrflowCore

// Every shortcut the user can change, in one list. See `Docs/shortcuts.md`.

/// How macOS is asked for a shortcut, which decides what the shortcut may be.
public enum ShortcutDelivery: Sendable, Equatable {
    /// Watched through the one event tap, which sees Fn and leaves the key doing what it did.
    case observed
    /// Registered as a hot key, which swallows the combination so nothing else acts on it too.
    case claimed
}

/// One bindable shortcut: what it is called, and what it does.
public struct ShortcutDescriptor: Sendable, Equatable {
    /// Which shortcut this describes.
    public let action: ShortcutAction
    /// The row's label, in the user's words rather than the code's.
    public let label: String
    /// One sentence under the label, or nothing when the label says it all.
    public let explanation: String?
    /// How the shortcut reaches this app, which decides whether it can be a held key.
    public let delivery: ShortcutDelivery
}

/// The list the shortcuts screen is drawn from; adding a shortcut is adding an entry here.
public enum ShortcutRegistry {
    /// Every shortcut, in the order the screen shows them.
    public static let all: [ShortcutDescriptor] = [
        ShortcutDescriptor(
            action: .dictate,
            label: "Dictate",
            explanation: "Hold to talk. Double-tap the same keys to keep talking hands-free.",
            delivery: .observed),
        ShortcutDescriptor(
            action: .clipboard,
            label: "Clipboard",
            explanation: "Opens the clipboard panel from any app.",
            delivery: .claimed),
        ShortcutDescriptor(
            action: .pasteLastTranscript,
            label: "Paste last transcript",
            explanation: "Puts the last thing you dictated at the caret. Never uses the clipboard.",
            delivery: .claimed),
        ShortcutDescriptor(
            action: .copyLastTranscript,
            label: "Copy last transcript",
            explanation: "Puts the last thing you dictated on the clipboard.",
            delivery: .claimed),
    ]

    /// Every shortcut macOS must swallow for us, which is where a hot key is registered.
    public static var claimed: [ShortcutDescriptor] { all.filter { $0.delivery == .claimed } }

    /// The entry for one action; every action has one, so this cannot fail.
    public static func descriptor(for action: ShortcutAction) -> ShortcutDescriptor {
        all.first { $0.action == action } ?? all[0]
    }

    /// What one action is called, for a sentence that has to name it.
    public static func label(for action: ShortcutAction) -> String {
        descriptor(for: action).label
    }
}
