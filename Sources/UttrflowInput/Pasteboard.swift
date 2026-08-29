public import UttrflowCore

/// The system clipboard, reduced to what insertion needs.
///
/// Behind a protocol because pasting borrows something that belongs to the user. Every
/// rule about giving it back is therefore testable without touching the real clipboard.
public protocol Pasteboard: Sendable {
    /// The current text, or `nil` when the clipboard holds something else.
    func text() -> String?
    /// Replaces the contents.
    func setText(_ text: String)

    /// The same write, with the formatted flavour alongside where there is one.
    func setText(_ text: String, richText: String?)
    /// Increments whenever anything changes the clipboard, including other apps.
    func changeCount() -> Int
}

/// Sends the keystroke that pastes.
public protocol KeystrokeSender: Sendable {
    /// Presses ⌘V.
    ///
    /// - Throws: ``TextInsertionError/accessibilityDenied`` when macOS will not let
    ///   this process post events.
    func sendPaste() throws(TextInsertionError)
}

extension Pasteboard {
    /// Defaulted so every existing implementation and every test double keeps working:
    /// a pasteboard that cannot carry formatting simply writes the words.
    public func setText(_ text: String, richText: String?) { setText(text) }
}
