public import UttrflowCore
public import struct Foundation.Data

/// The system clipboard, reduced to what insertion needs and testable without touching the real one.
public protocol Pasteboard: Sendable {
    /// The current text, or `nil` when the clipboard holds something else.
    func text() -> String?
    /// Replaces the contents.
    func setText(_ text: String)

    /// The same write, with the formatted flavour alongside where there is one.
    func setText(_ text: String, richText: String?)

    /// K4 — replaces the contents with a picture, as PNG bytes, so no caller needs the platform clipboard.
    func setImage(_ data: Data)
}

/// Sends the keystroke that pastes.
public protocol KeystrokeSender: Sendable {
    /// Presses ⌘V, refusing with ``TextInsertionError/accessibilityDenied`` where macOS forbids it.
    func sendPaste() throws(TextInsertionError)
}

extension Pasteboard {
    /// A pasteboard that cannot carry formatting simply writes the words.
    public func setText(_ text: String, richText: String?) { setText(text) }
}
