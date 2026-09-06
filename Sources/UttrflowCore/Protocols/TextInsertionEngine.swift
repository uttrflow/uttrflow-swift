// The strategies for putting finished text into another application, and how each one reports itself.
/// How text reached the target application, recorded so the harness sees which strategy carries traffic.
public enum TextInsertionMethod: String, Sendable, Equatable, CaseIterable, Codable {
    /// Written straight into the focused element through the Accessibility API.
    case accessibility
    /// Placed on the clipboard and pasted with a synthetic key event.
    case pasteboard
    /// Left on the clipboard, with nothing typed anywhere, so the user still has to press ⌘V.
    case clipboard
    /// Typed in as key events, character by character, with the clipboard left alone.
    case typed
}

/// Places finished text into whatever the user is typing in, never over an unselected word.
public protocol TextInsertionEngine: Sendable {
    /// How this strategy reports itself.
    var method: TextInsertionMethod { get }

    /// Whether this strategy can insert into what is currently focused.
    func canInsert() async -> Bool

    /// Puts `text` where the user is typing.
    func insert(_ text: String) async throws(TextInsertionError)

    /// Inserts, carrying the formatted form where the strategy has a way to; only the pasteboard has one.
    func insert(_ text: String, richText: String?) async throws(TextInsertionError)
}

extension TextInsertionEngine {
    /// Ignores the formatted form, because writing into a focused element carries no formatting.
    public func insert(_ text: String, richText: String?) async throws(TextInsertionError) {
        try await insert(text)
    }
}
