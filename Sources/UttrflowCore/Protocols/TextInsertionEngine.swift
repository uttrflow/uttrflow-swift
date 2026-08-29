/// How text reached the target application. Recorded so the evaluation harness can
/// see which strategy actually carries real-world traffic.
public enum TextInsertionMethod: String, Sendable, Equatable, CaseIterable, Codable {
    /// Written straight into the focused element through the Accessibility API.
    case accessibility
    /// Placed on the clipboard and pasted with a synthetic key event.
    case pasteboard
    /// Left on the clipboard, with nothing typed anywhere.
    ///
    /// Distinct from ``pasteboard`` because the difference is the whole story for the
    /// user: one put the words where they were looking, the other did not and needs
    /// them to press ⌘V. Both used to report `pasteboard`, so the interface said
    /// "Inserted" for a dictation that had gone nowhere near their document.
    case clipboard
}

/// Places finished text into whatever the user is typing in.
///
/// An implementation must never replace content the user did not select.
public protocol TextInsertionEngine: Sendable {
    var method: TextInsertionMethod { get }

    /// Whether this strategy can insert into what is currently focused.
    func canInsert() async -> Bool

    func insert(_ text: String) async throws(TextInsertionError)

    /// E2 — insert, carrying the formatted form where the strategy has a way to.
    ///
    /// Defaulted to ignoring it, because most strategies genuinely have none: writing a
    /// string into a focused element carries no formatting and pretending otherwise would
    /// be the silent kind of wrong. Only the pasteboard route can honour it.
    func insert(_ text: String, richText: String?) async throws(TextInsertionError)
}

extension TextInsertionEngine {
    public func insert(_ text: String, richText: String?) async throws(TextInsertionError) {
        try await insert(text)
    }
}
