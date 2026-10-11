import AppKit

/// A window that never becomes the active one, so the caret stays in the field under it.
final class SuggestionPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
