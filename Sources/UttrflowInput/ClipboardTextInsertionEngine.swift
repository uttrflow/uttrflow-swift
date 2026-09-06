public import UttrflowCore

/// The last resort: leaves the text on the clipboard and says so, so the words are never lost.
public struct ClipboardTextInsertionEngine: TextInsertionEngine {
    /// Not `.pasteboard`: this says the words are waiting, where that says a paste landed.
    public let method: TextInsertionMethod = .clipboard

    private let pasteboard: any Pasteboard

    public init(pasteboard: any Pasteboard) {
        self.pasteboard = pasteboard
    }

    /// Always. A clipboard is always available, which is the point of having this.
    public func canInsert() async -> Bool { true }

    public func insert(_ text: String) async throws(TextInsertionError) {
        pasteboard.setText(text)
        guard pasteboard.text() == text else { throw .clipboardUnavailable }
    }
}
