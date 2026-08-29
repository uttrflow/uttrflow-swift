public import UttrflowCore

/// The last resort: leave the text on the clipboard and say so.
///
/// Not really insertion, and deliberately not pretending to be — it reports
/// ``TextInsertionMethod/clipboard`` and succeeds, so the words are never lost even
/// when nothing on screen will take them.
///
/// It used to report ``TextInsertionMethod/pasteboard``, the same value a successful
/// paste returns, which left the interface unable to tell the two apart: it said
/// "Inserted" for a dictation that had gone nowhere near the user's document. The
/// separate case is what lets the caller say where the words actually are.
public struct ClipboardTextInsertionEngine: TextInsertionEngine {
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
